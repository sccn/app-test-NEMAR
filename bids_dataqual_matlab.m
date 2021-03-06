function bids_dataqual_matlab(filepath, outpath, root_path)
addpath(root_path);
load_eeglab(root_path);
%filepath = dataset;%'/Volumes/LaCie/BIDS/ds002718-download';
modeval = 'read';

tic;

%filepath = pwd;
[root_dir,dsname] = fileparts(filepath);
if ~isempty(outpath)
    outputDir = fullfile(outpath, dsname);
else
    outputDir = fullfile(root_dir, 'processed', dsname);
end
disp(['outputdir ' outputDir]);
disp(['inputdir ' filepath]);
dir(filepath);
%filepath = '/Users/arno/temp/BIDS_export_p300/BIDS_EXPORT';
%filepath = '/data/data/STUDIES/BIDS_hw';
%filepath = '/data/data/STUDIES/BIDS_EXPORT';
%filepath = '/Users/arno/GoogleDrive/bids_p3_2subjects/BIDS';

% clear error log file
fid = fopen(sprintf('%s/processing-log/%s_err.txt',root_path,dsname),'w');
fprintf(fid, '');
fclose(fid);

% read or import data
%pop_editoptions( 'option_storedisk', 1);
useBidsChans = { 'ds002718' 'ds003190' 'ds002578' 'ds002887' 'ds003004' 'ds002833' 'ds002691' 'ds002791' 'ds001787' 'ds003474', 'ds003645' };
studyFile = fullfile(outputDir, [dsname '.study']);
if ~exist(studyFile, 'file') || strcmpi(modeval, 'import')
    %if exist(outputDir)
        %system([ 'rm -r --force ' outputDir ]);
    %end
    if ismember(dsname, useBidsChans), bidsChan = 'on'; else bidsChan = 'off'; end
    disp(['bidsChan ' bidsChan]);
    [STUDY, ALLEEG] = pop_importbids(filepath, 'bidsevent','off','bidschanloc', bidsChan,'studyName',dsname,'outputdir', outputDir);
else
    tic
    [STUDY, ALLEEG] = pop_loadstudy(studyFile);
end
if any([ ALLEEG.trials ] > 1)
    disp('Cannot process data epochs');
end
nChans              = zeros(1, length(ALLEEG))*NaN;
percentChanRejected = zeros(1, length(ALLEEG))*NaN;
percentDataRejected = zeros(1, length(ALLEEG))*NaN;
percentBrainICs     = zeros(1, length(ALLEEG))*NaN;
asrFail             = zeros(1, length(ALLEEG));
icaFail             = zeros(1, length(ALLEEG));
try
    %parpool;
catch
    warning('starting parpool failed. parpool might already be created');
end

for iDat = 1:length(ALLEEG)
try
    EEG = ALLEEG(iDat);
    
    processedEEG = [ EEG.filename(1:end-4) '_processed.set' ];
    if ~exist(fullfile(EEG.filepath, processedEEG), 'file')
        fprintf('Processing dataset %s\n', EEG.filename);
        EEG = eeg_checkset(EEG, 'loaddata');
        
        %allVars = whos;
        %fprintf('******** Memory used (Mb) %d/n', round(sum([allVars.bytes])/1e6));
        
        % check channel locations
        % remove non-EEG channels
        disp('Selecting channels based on type...');
        try
            dipfit_path = fileparts(which('pop_dipplot'));
        catch
            dipfit_path = fullfile(root_path, 'eeglab','plugins','dipfit');
        end
        chanfile = [dipfit_path '/standard_BEM/elec/standard_1005.elc'];
        if ~exist(chanfile,'file')
            chanfile = '/home/octave/eeglab/plugins/dipfit/standard_BEM/elec/standard_1005.elc';
        end
        if isfield(EEG.chanlocs, 'theta')
            notEmpty = ~cellfun(@isempty, { EEG.chanlocs.theta });
            if any(notEmpty)
                EEG = pop_select(EEG, 'channel', find(notEmpty));
            else
                EEG = pop_chanedit(EEG, 'lookup',chanfile);
            end
        else
            EEG = pop_chanedit(EEG, 'lookup',chanfile);
        end
        notEmpty = ~cellfun(@isempty,  { EEG.chanlocs.theta });
        EEG = pop_select(EEG, 'channel', find(notEmpty));
       
        % resample ds002336
        if EEG.srate == 5000
            EEG = pop_resample(EEG, 250); % instead of 5000 Hz (ds002336 and ds002338)
        end
 
        % remove DC
        disp('Remove DC');
        EEG = pop_rmbase(EEG, [EEG.times(1) EEG.times(end)]);
        EEG.etc.orinbchan = EEG.nbchan;
        EEG.etc.oripnts   = EEG.pnts;

        if any(any(EEG.data')) % not all data is 0
            % remove bad channels
            disp('Call clean_rawdata...');
            try
                EEGTMP = pop_clean_rawdata( EEG,'FlatlineCriterion',5,'ChannelCriterion',0.8,'LineNoiseCriterion',4,'Highpass',[0.25 0.75] ,...
                    'BurstCriterion',20,'WindowCriterion',0.25,'BurstRejection','on','Distance','Euclidian','WindowCriterionTolerances',[-Inf 7] );
                EEG = EEGTMP;
		
		result_basename = EEG.filename(1:end-4); % for plots

		        % save EEGPLOT
                % ------------
                bounds = strmatch('boundary', { EEG.event.type });
                startLat = round(length(EEG.times)/2);
                if ~isempty(bounds)
                    boundLat = [ EEG.event(bounds).latency ];
                    diffLat = diff(boundLat);
                    indLat = find(diffLat > EEG.srate*2); % 2 seconds of good data
                    if ~isempty(indLat)
                        startLat = boundLat(indLat(1));
                    end
                end
		% redo eegplot
		eegplot(EEG.data(:,startLat:startLat+EEG.srate*2), 'srate', EEG.srate, ...
		    'winlength', 2, 'eloc_file', EEG.chanlocs, 'noui', 'on', 'title','');
		print(gcf,'-dsvg','-noui',fullfile(EEG.filepath, [ result_basename '_eegplot.svg' ]))
		close

		% spectopo plot
		figure;
		[spec,~] = spectopo(EEG.data, 0, EEG.srate, 'freq', [6, 10, 22], 'freqrange', [1 70], 'title', '', 'chanlocs', EEG.chanlocs, 'percent', 10,'plot', 'on');
		print(gcf,'-dsvg','-noui',fullfile(EEG.filepath,[ result_basename '_spectopo.svg' ]))
		close


                % run ICA and IC label
                %if ~isempty(EEG.chanlocs) && isfield(EEG.chanlocs, 'X') && ~isempty(EEG.chanlocs(1).X)
                try
		    EEG = pop_reref(EEG, []);
                    amicaout = fullfile(EEG.filepath, 'amicaout');
                    if exist(amicaout, 'dir')
                        EEG = eeg_loadamica(EEG, fullfile(EEG.filepath, 'amicaout'));
                    else
                        EEG = pop_runamica(EEG,'numprocs',1, 'do_reject', 1, 'numrej', 5, 'rejint', 4,'rejsig', 3,'rejstart', 1, 'pcakeep',EEG.nbchan-1); % Computing ICA with AMICA
                        EEG = eeg_loadamica(EEG, fullfile(EEG.filepath, 'amicaout'));
                        % rmdir( fullfile(EEG.filepath, 'amicaout'), 's');
                    end
                    % EEG = pop_runica(EEG, 'icatype','picard','options',{'pca',EEG.nbchan-1});
                    EEG = pop_iclabel(EEG,'default');
                    EEG = pop_icflag(EEG,[0.6 1;NaN NaN;NaN NaN;NaN NaN;NaN NaN;NaN NaN;NaN NaN]);

		% IC activations plot
		iclocs = EEG.chanlocs;
		% trick to set plot X axis labels to be ICs instead of EEG channels
		for idx=1:numel(iclocs)
		    iclocs(idx).labels = ['IC' num2str(idx)];
		end
                startLat = round(length(EEG.times)/2);
		figure;
		tmp = EEG.icaweights*EEG.icasphere*EEG.data(:,startLat:startLat+EEG.srate*2);
		eegplot(tmp, 'srate', EEG.srate, ...
		    'winlength', 2, 'eloc_file', iclocs, 'noui', 'on', 'title', '');
		h = findall(gcf,'-property','FontName');
		set(h,'FontName','San Serif');
		print(gcf,'-dsvg',fullfile(EEG.filepath, [ result_basename '_icaact.svg' ]))
		close

                    % Save IC Label image for first 28 ICs (4x7)
                    % -------------------
			pop_viewprops( EEG, 0, [1:28], {'freqrange', [2 64]}, {}, 1, 'ICLabel' );
			print(gcf,'-dsvg','-noui',fullfile(EEG.filepath,[ result_basename '_icamaps.svg' ]))
			close

                    disp(fullfile(EEG.filepath, processedEEG));
                    pop_saveset(EEG, fullfile(EEG.filepath, processedEEG));
                catch ME
                    l = lasterror
                    s=dbstack;
                    fid = fopen(sprintf('%s/processing-log/%s_err.txt',root_path,dsname),'a');
                    fprintf(fid, 'File %s, line %d, %s: %s\n', EEG.filename, s(1).line, ME.identifier, ME.message);
                    fclose(fid);
                    for iL = 1:length(l.stack)
                        l.stack(iL)
                    end
                    icaFail(iDat) = 1;
                end
            catch ME
                l = lasterror
                s=dbstack;
                fid = fopen(sprintf('%s/processing-log/%s_err.txt',root_path,dsname),'a');
                fprintf(fid, 'File %s, line %d, %s: %s\n', EEG.filename, s(1).line, ME.identifier, ME.message);
                fclose(fid);

                for iL = 1:length(l.stack)
                    l.stack(iL)
                end
                asrFail(iDat) = 1;
            end
        else
            asrFail(iDat) = 1;
        end
    else
        % do not load binary data
        fprintf('Loading dataset %s\n', processedEEG);
	EEG = pop_loadset(fullfile(EEG.filepath, processedEEG));

        result_basename = erase(EEG.filename, '_processed.set');

        startLat = round(length(EEG.times)/2);

	% redo eegplot
	eegplot(EEG.data(:,startLat:startLat+EEG.srate*2), 'srate', EEG.srate, ...
	    'winlength', 2, 'eloc_file', EEG.chanlocs, 'noui', 'on', 'title','');
	print(gcf,'-dsvg','-noui',fullfile(EEG.filepath, [ result_basename '_eegplot.svg' ]))
	close

	% spectopo plot
	figure;
	[spec,~] = spectopo(EEG.data, 0, EEG.srate, 'freq', [6, 10, 22], 'freqrange', [1 70], 'title', '', 'chanlocs', EEG.chanlocs, 'percent', 10,'plot', 'on');
        print(gcf,'-dsvg','-noui',fullfile(EEG.filepath,[ result_basename '_spectopo.svg' ]))
	close

	% IC activations plot
	iclocs = EEG.chanlocs;
	% trick to set plot X axis labels to be ICs instead of EEG channels
	for idx=1:numel(iclocs)
	    iclocs(idx).labels = ['IC' num2str(idx)];
	end
	figure;
	tmp = EEG.icaweights*EEG.icasphere*EEG.data(:,startLat:startLat+EEG.srate*2);
	eegplot(tmp, 'srate', EEG.srate, ...
	    'winlength', 2, 'eloc_file', iclocs, 'noui', 'on', 'title', '');
	h = findall(gcf,'-property','FontName');
	set(h,'FontName','San Serif');
	print(gcf,'-dsvg',fullfile(EEG.filepath, [ result_basename '_icaact.svg' ]))
	close

	% redo ICLabel plot (temp)
        pop_viewprops( EEG, 0, [1:28], {'freqrange', [2 64]}, {}, 1, 'ICLabel' );
        print(gcf,'-dsvg','-noui',fullfile(EEG.filepath,[ result_basename '_icamaps.svg' ]))
        close

    end
    % get results
    if contains(EEG.filename, 'processed')
        result_basename = erase(EEG.filename, '_processed.set');
    else
        result_basename = erase(EEG.filename, '.set');
    end
    if ~asrFail(iDat) && ~icaFail(iDat)
        numChans = EEG.etc.orinbchan;
        goodChans = EEG.nbchan/EEG.etc.orinbchan;
        goodData = EEG.pnts/EEG.etc.oripnts;
	numFrames = EEG.etc.oripnts;
        goodICA = sum(EEG.reject.gcompreject)/(EEG.nbchan-1);
	numICs = EEG.nbchan-1;
        percentBrainICs(iDat) = goodICA;
        nChans(iDat) = numChans;
        percentChanRejected(iDat) = 1-goodChans;
        percentDataRejected(iDat) = 1-goodData;
        save_dataqual_results(EEG.filepath, result_basename, asrFail(iDat), icaFail(iDat), numChans, goodChans, goodData, goodICA, numFrames, numICs);
    else
        numChans = EEG.etc.orinbchan;
        goodChans = nan;
        goodData = nan;
        goodICA = nan;
	numFrames = length(EEG.times);
	numICs = EEG.nbchan-1;
        save_dataqual_results(EEG.filepath, result_basename, asrFail(iDat), icaFail(iDat), numChans, goodChans, goodData, goodICA, numFrames, numICs);
    end
catch ME
	s=dbstack;
	fid = fopen(sprintf('%s/processing-log/%s_err.txt',root_path,dsname),'a');
	fprintf(fid, 'File %s, line %d, %s: %s\n', EEG.filename, s(1).line, ME.identifier, ME.message);
	fclose(fid);

end
end

%nChans
%percentChanRejected
%percentDataRejected
%percentBrainICs
%asrFail
%icaFail

nChans(isnan(nChans)) = [];
percentChanRejected(isnan(percentChanRejected)) = [];
percentDataRejected(isnan(percentDataRejected)) = [];
percentBrainICs(isnan(percentBrainICs)) = [];
asrFail(isnan(asrFail)) = [];
icaFail(isnan(icaFail)) = [];

timeItTook = toc
timeItTook2 = timeItTook/3600/24;
hoursStr = datestr(timeItTook2, 'HH');
minStr   = datestr(timeItTook2, 'MM');

ciChan  = [NaN NaN];
ciData  = [NaN NaN];
ciBrain = [NaN NaN];
try
    ciChan = bootci(200, { @mean 1-percentChanRejected }, 'type', 'per');
    ciData = bootci(200, { @mean 1-percentDataRejected }, 'type', 'per');
    ciBrain = bootci(200, { @mean percentBrainICs }, 'type', 'per');
catch
end

res.timeSec   = sprintf('%d', round(timeItTook));
res.timeHours = sprintf('%d:%2.2d', round(timeItTook2)*24+str2num(hoursStr), str2num(minStr));
res.nChans    = sprintf('%d-%d', min(nChans), max(nChans));
res.goodChans = sprintf('%1.1f-%1.1f', ciChan(1)*100, ciChan(2)*100);
res.goodData  = sprintf('%1.1f-%1.1f', ciData(1)*100, ciData(2)*100);
res.goodICA   = sprintf('%1.1f-%1.1f', ciBrain(1)*100, ciBrain(2)*100);
res.asrFail   = sprintf('%d/%d', sum(asrFail), length(asrFail));
res.icaFail   = sprintf('%d/%d', sum(icaFail), length(icaFail));

fid = fopen(fullfile(outputDir, 'dataqual.txt'), 'w');
if fid ~= -1
    fprintf(fid, '%s\n', res.timeSec);
    fprintf(fid, '%s\n', res.timeHours);
    fprintf(fid, '%s\n', res.nChans);
    fprintf(fid, '%s\n', res.asrFail);
    fprintf(fid, '%s\n', res.icaFail);
    fprintf(fid, '%s\n', res.goodChans);
    fprintf(fid, '%s\n', res.goodData);
    fprintf(fid, '%s\n', res.goodICA);
    fclose(fid);
end

fid = fopen(fullfile(outputDir, 'dataqual.json' ), 'w');
if fid ~= -1
    fprintf(fid, '%s\n', jsonwrite(res));
    fclose(fid);
end

function save_dataqual_results(filepath, filename, asrStatus, icaStatus, numChans, goodChans, goodData, goodICA, numFrames, numICs)
    res.nChans    = sprintf('%d', numChans);
    res.nFrames    = sprintf('%d', numFrames);
    res.nICs    = sprintf('%d', numICs);
    res.goodChans = sprintf('%1.1f', goodChans*100);
    res.nGoodChans = sprintf('%d', goodChans*numChans);
    res.goodData  = sprintf('%1.1f', goodData*100);
    res.nGoodData = sprintf('%d', goodData*numFrames);
    res.goodICA   = sprintf('%1.1f', goodICA*100);
    res.nGoodICs  = sprintf('%d', goodICA*numICs); 
    res.asrFail   = sprintf('%d', asrStatus);
    res.icaFail   = sprintf('%d', icaStatus);
    res
    fid = fopen(fullfile(filepath, [filename '_dataqual.json'] ), 'w');
    if fid ~= -1
        fprintf(fid, '%s\n', jsonwrite(res));
        fclose(fid);
    end



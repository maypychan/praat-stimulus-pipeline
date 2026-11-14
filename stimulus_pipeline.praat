###############################################################
## Stimulus recording pipeline, version 1.0.0
## May Pik Yu Chan, 2026 - MIT License
## https://github.com/maypychan/praat-stimulus-pipeline
##
## 1. segments a recording of a word list into words and silences
## 2. opens the editor until the number of words matches the csv
## 3. labels the words from the csv, in order
## 4. opens the editor for a final check
## 5. cuts each word into its own wav file (padding, fades, normalization, added silence)
##
## Silent intervals are labelled "xxx"; every other interval is a word.
## Output goes into a subfolder named after the recording.
## Relative paths are read relative to the folder of this script.
## Paths can use / or \ on both Windows and Mac (\ is turned into /).
###############################################################

form Stimulus recording pipeline
	comment Files (paths relative to this script; / and \ both work)
	sentence sound_file example/demo_list.wav
	sentence csv_file example/demo_list.csv
	word stimuli_column stimuli
	natural repetitions_per_word 1
	sentence output_folder output
	comment Export repetitions, e.g. 2 5: also copies every word_2 / word_5 file into stims_2 / stims_5
	sentence export_repetitions
	comment Cutting (ms): padding around each word, fade at the edges, silence added to the file
	real padding_ms 20
	real fade_ms 5
	real leading_silence_ms 0
	real trailing_silence_ms 0
	comment Normalization (target duration 0 = no duration normalization)
	optionmenu amplitude_normalization 1
		option none
		option peak
		option intensity (RMS)
	positive target_intensity_db 70
	real target_duration_ms 0
	comment Optional first step: correct a stretch at the start by hand, then test segmentation settings on it
	boolean tune_settings 0
	positive tuning_stretch_s 180
	boolean advanced_settings 0
endform

###
## advanced settings defaults
minimum_pitch = 100
time_step = 0
silence_threshold = -30
auto_threshold = 0
minimum_silent_interval = 0.2
minimum_sounding_interval = 0.1
merge_split_words = 1
merge_max_pause = 0.35
merge_max_ratio = 1.6
widen_edges = 1
edge_threshold = -40
edge_max = 0.2
short_interval = 100
long_interval = 1500
check_repetition_pattern = 1
target_peak = 0.99
maximum_pitch = 600

if advanced_settings
	beginPause: "Advanced settings"
		comment: "Silence detection (To TextGrid (silences)) - pitch in Hz, times in s, threshold in dB re. maximum"
		positive: "Minimum pitch", minimum_pitch
		real: "Time step", time_step
		real: "Silence threshold", silence_threshold
		boolean: "Auto threshold", auto_threshold
		positive: "Minimum silent interval", minimum_silent_interval
		positive: "Minimum sounding interval", minimum_sounding_interval
		comment: "Merge split words: join intervals across pauses shorter than (s) if the result is at most (x median word)"
		boolean: "Merge split words", merge_split_words
		positive: "Merge max pause", merge_max_pause
		positive: "Merge max ratio", merge_max_ratio
		comment: "Widen edges: widen each word while the intensity is above (dB re. maximum), by at most (s)"
		boolean: "Widen edges", widen_edges
		real: "Edge threshold", edge_threshold
		positive: "Edge max", edge_max
		comment: "Checks, flagged on the guide tier - flag words shorter / longer than (ms)"
		positive: "Short interval", short_interval
		positive: "Long interval", long_interval
		boolean: "Check repetition pattern", check_repetition_pattern
		comment: "Peak normalization target (0-1), and maximum pitch (Hz) for duration normalization"
		positive: "Target peak", target_peak
		positive: "Maximum pitch", maximum_pitch
	clicked = endPause: "Stop", "Continue", 2, 1
	if clicked = 1
		exitScript: "Stopped by user."
	endif
endif

clearinfo
silent_label$ = "xxx"

## forward slashes work on Windows, Mac and Linux; backslashes only on Windows
sound_file$ = replace$ (sound_file$, "\", "/", 0)
csv_file$ = replace$ (csv_file$, "\", "/", 0)
output_folder$ = replace$ (output_folder$, "\", "/", 0)
setup_info$ = ""

padding = padding_ms / 1000
fade = fade_ms / 1000
target_duration = target_duration_ms / 1000
leading_silence = leading_silence_ms / 1000
trailing_silence = trailing_silence_ms / 1000

createFolder: output_folder$
if right$(output_folder$, 1) <> "/"
	output_folder$ = output_folder$ + "/"
endif

## export repetitions, e.g. "2 5" or "2, 5"
export_parts$# = splitByWhitespace$# (replace$ (export_repetitions$, ",", " ", 0))
n_export = size (export_parts$#)
if n_export > 0
	export# = zero# (n_export)
	for ex from 1 to n_export
		export# [ex] = number (export_parts$# [ex])
		if export# [ex] = undefined
			exitScript: "Export repetitions should be whole numbers like 2 5, not: ", export_parts$# [ex]
		elsif export# [ex] < 1 or export# [ex] <> round (export# [ex])
			exitScript: "Export repetitions should be whole numbers like 2 5, not: ", export_parts$# [ex]
		endif
	endfor
endif

###
## read the recording
sound = Read from file: sound_file$
sound_name$ = selected$("Sound")
n_channels = Get number of channels
if n_channels > 1
	mono = Convert to mono
	removeObject: sound
	sound = mono
	Rename: sound_name$
	setup_info$ = setup_info$ + "Converted " + string$(n_channels) + " channels to mono." + newline$
endif
sound_duration = Get total duration
sampling_rate = Get sampling frequency

###
## output subfolder; if in use, overwrite or use name_2, name_3, ...
recording_folder$ = sound_name$
@countFiles: output_folder$ + recording_folder$
if countFiles.n > 0
	@askOutputFolder: countFiles.n, output_folder$ + recording_folder$
	if askOutputFolder.clicked = 3
		folder_n = 1
		while countFiles.n > 0
			folder_n += 1
			recording_folder$ = sound_name$ + "_" + string$(folder_n)
			@countFiles: output_folder$ + recording_folder$
		endwhile
	endif
endif
output_folder$ = output_folder$ + recording_folder$ + "/"
setup_info$ = setup_info$ + "Saving into " + output_folder$ + newline$

table = Read Table from comma-separated file: csv_file$
stimuli_nrows = Get number of rows
column_index = Get column index: stimuli_column$
if column_index = 0
	exitScript: "Cannot find a column called """, stimuli_column$, """ in ", csv_file$
endif

n_expected = stimuli_nrows * repetitions_per_word
setup_info$ = setup_info$ + "Expecting " + string$(n_expected) + " words (" + string$(stimuli_nrows)
... + " csv rows x " + string$(repetitions_per_word) + ")." + newline$

## change# [k] = 1 if expected word k differs from the previous one
change# = zero# (n_expected)
prev_value$ = ""
for k from 1 to n_expected
	stimuli_value$ = Get value: ceiling(k / repetitions_per_word), stimuli_column$
	change# [k] = (stimuli_value$ <> prev_value$)
	prev_value$ = stimuli_value$
endfor

###
## auto threshold: midpoint of the 25th and 75th intensity percentiles, re. maximum
if auto_threshold
	selectObject: sound
	intensity = To Intensity: minimum_pitch, time_step, "yes"
	p25 = Get quantile: 0, 0, 0.25
	p75 = Get quantile: 0, 0, 0.75
	max_db = Get maximum: 0, 0, "parabolic"
	removeObject: intensity

	auto_value = (p25 + p75) / 2 - max_db
	## digital silence gives -300 dB frames
	if p25 > -100 and auto_value < 0
		silence_threshold = auto_value
		setup_info$ = setup_info$ + "Auto threshold: " + fixed$(silence_threshold, 1) + " dB re. maximum (25th pct "
		... + fixed$(p25, 1) + " dB, 75th pct " + fixed$(p75, 1) + " dB, max " + fixed$(max_db, 1) + " dB)" + newline$
	else
		setup_info$ = setup_info$ + "WARNING: auto threshold failed (25th pct " + fixed$(p25, 1)
		... + " dB), using " + string$(silence_threshold) + " dB instead." + newline$
	endif
endif

###
## intensity as in To TextGrid (silences), computed once and reused
selectObject: sound
filtered = Filter (pass Hann band): 80, 8000, 80
intensity = To Intensity: minimum_pitch, time_step, "yes"
removeObject: filtered
intensity_max = Get maximum: 0, 0, "parabolic"
noise_floor = Get quantile: 0, 0, 0.1
noise_floor = noise_floor - intensity_max
frame_t1 = Get time from frame number: 1
frame_dt = Get time step
intensity_matrix = Down to Matrix
intensity## = Get all values
n_frames = numberOfColumns (intensity##)
removeObject: intensity_matrix

###
## optional settings tuning
keep_stretch = 0
if tune_settings
	@tuneSettings
endif

###
## automatic segmentation
@checkNoiseFloor
@segment: silence_threshold, minimum_silent_interval, minimum_sounding_interval, merge_split_words, widen_edges, sound_duration
if keep_stretch
	@spliceStretch
endif
@makeTextGrid
setup_info$ = setup_info$ + "Segmentation: threshold " + fixed$(silence_threshold, 1) + " dB, minimum silent "
... + string$(minimum_silent_interval) + " s, minimum sounding " + string$(minimum_sounding_interval) + " s"
... + if merge_split_words then ", split words merged (" + string$(segment.n_merged) + ")" else "" fi
... + if widen_edges then ", edges widened to " + string$(edge_threshold) + " dB" else "" fi + "." + newline$

###
## fix the count, label, final check
first_pass = 1
cut_now = 0

while cut_now = 0
	@fixCount: first_pass
	first_pass = 0
	@slotLabels
	@checkTextGrid: 0

	pause_text$ = "All " + string$(n_expected) + " words are labelled from the csv, in order." + newline$
	... + newline$
	... + checkTextGrid.summary$ + newline$
	... + newline$
	... + "Added, removed or moved boundaries?" + newline$
	... + "     Click Relabel from csv to fill in the csv words again, in order." + newline$
	... + "     (This replaces any labels you typed yourself.)" + newline$
	... + newline$
	... + "The guide tier (tier 2) shows word numbers, expected words and warnings." + newline$
	... + "     It is only a guide - it is not used for cutting." + newline$
	... + newline$
	... + "Click Cut stimuli when you are done." + newline$
	... + "Please don't close the editor window yourself."
	@pauseEditor: "Check the labels", pause_text$, "Stop", "Relabel from csv", "Cut stimuli"

	if pauseEditor.clicked = 3
		@checkTextGrid: 0
		if checkTextGrid.n_words = n_expected
			cut_now = 1
		else
			appendInfoLine: "The number of words changed during the final check - back to fixing the count."
		endif
	endif
endwhile

selectObject: textgrid
Save as text file: output_folder$ + sound_name$ + ".TextGrid"

###
## log table of the stimulus intervals
selectObject: textgrid
n_intervals = Get number of intervals: 1
log = Create Table with column names: "log", 0, "n label file rep start end word_ms file_ms clipped note"
n_stimuli = 0

for m from 1 to n_intervals
	selectObject: textgrid
	intvl_lbl$ = Get label of interval: 1, m

	if intvl_lbl$ <> silent_label$ and intvl_lbl$ <> ""
		intvl_start = Get start time of interval: 1, m
		intvl_end = Get end time of interval: 1, m
		n_stimuli += 1

		selectObject: log
		Append row
		Set numeric value: n_stimuli, "n", n_stimuli
		Set string value: n_stimuli, "label", intvl_lbl$
		Set numeric value: n_stimuli, "start", intvl_start
		Set numeric value: n_stimuli, "end", intvl_end
	endif
endfor

###
## file names: repeated words are numbered in recording order (sorted by label, then back)
selectObject: log
Sort rows: "label n"
row = 1

while row <= n_stimuli
	label$ = Get value: row, "label"
	file$ = replace$(label$, "\", "_", 0)
	file$ = replace_regex$(file$, "[/:*?""<>| ]", "_", 0)

	group_end = row
	same_label = 1
	while same_label and group_end < n_stimuli
		next_label$ = Get value: group_end + 1, "label"
		if next_label$ = label$
			group_end += 1
		else
			same_label = 0
		endif
	endwhile

	for k from row to group_end
		if group_end > row
			Set string value: k, "file", file$ + "_" + string$(k - row + 1)
			Set numeric value: k, "rep", k - row + 1
		else
			Set string value: k, "file", file$
			Set numeric value: k, "rep", 1
		endif
	endfor

	row = group_end + 1
endwhile

Sort rows: "n"

###
## duration tables for the exported repetitions
for ex from 1 to n_export
	if ex = 1
		export_table# = zero# (n_export)
	endif
	export_table# [ex] = Create Table with column names: "sf_dur_" + string$(export# [ex]), 0, "sound_file_name sound_duration"
endfor

###
## cut, normalize and save each stimulus
for n from 1 to n_stimuli
	selectObject: log
	file$ = Get value: n, "file"
	intvl_start = Get value: n, "start"
	intvl_end = Get value: n, "end"
	note$ = ""

	selectObject: sound
	stimulus = Extract part: intvl_start, intvl_end, "rectangular", 1, "no"

	## duration normalization (Lengthen needs at least 3 pitch periods)
	if target_duration > 0
		word_duration = Get total duration
		if word_duration * minimum_pitch < 3
			note$ = "too short to normalize duration"
			appendInfoLine: "WARNING: ", file$, " is only ", fixed$(word_duration * 1000, 0), " ms - duration left unchanged."
		else
			## Lengthen stretches at most 3x, so larger factors are done in steps
			factor = target_duration / word_duration
			n_steps = max(1, ceiling(ln(factor) / ln(3) - 1e-9))
			for step from 1 to n_steps
				selectObject: stimulus
				lengthened = Lengthen (overlap-add): minimum_pitch, maximum_pitch, factor ^ (1 / n_steps)
				removeObject: stimulus
				stimulus = lengthened
			endfor
			if n_steps > 1
				note$ = "stretched " + fixed$(factor, 1) + "x in " + string$(n_steps) + " steps"
			endif
		endif
	endif

	## sample count, as Get total duration can be wrong after Lengthen
	selectObject: stimulus
	word_duration = Get number of samples
	word_duration = word_duration / sampling_rate
	word_db = Get intensity (dB)

	## padding
	pad_start = max(0, intvl_start - padding)
	pad_end = min(sound_duration, intvl_end + padding)

	if pad_start < intvl_start
		selectObject: sound
		pre = Extract part: pad_start, intvl_start, "rectangular", 1, "no"
		@joinSounds: pre, stimulus
		removeObject: pre, stimulus
		stimulus = joinSounds.result
	endif

	if pad_end > intvl_end
		selectObject: sound
		post = Extract part: intvl_end, pad_end, "rectangular", 1, "no"
		@joinSounds: stimulus, post
		removeObject: stimulus, post
		stimulus = joinSounds.result
	endif

	## raised-cosine fades
	if fade > 0
		selectObject: stimulus
		stimulus_duration = Get total duration
		fade_now = min(fade, stimulus_duration / 2)
		Formula: "if x - xmin < " + string$(fade_now) + " then self * (1 - cos(pi * (x - xmin) / " + string$(fade_now) + ")) / 2"
		... + " else if xmax - x < " + string$(fade_now) + " then self * (1 - cos(pi * (xmax - x) / " + string$(fade_now) + ")) / 2"
		... + " else self fi fi"
	endif

	## amplitude normalization
	selectObject: stimulus
	if amplitude_normalization = 2
		Scale peak: target_peak
	elsif amplitude_normalization = 3
		gain = 10 ^ ((target_intensity_db - word_db) / 20)
		Formula: "self * " + string$(gain)
	endif

	## added silence
	if leading_silence > 0
		silence = Create Sound from formula: "silence", 1, 0, leading_silence, sampling_rate, "0"
		@joinSounds: silence, stimulus
		removeObject: silence, stimulus
		stimulus = joinSounds.result
	endif

	if trailing_silence > 0
		silence = Create Sound from formula: "silence", 1, 0, trailing_silence, sampling_rate, "0"
		@joinSounds: stimulus, silence
		removeObject: stimulus, silence
		stimulus = joinSounds.result
	endif

	## save
	selectObject: stimulus
	stimulus_duration = Get number of samples
	stimulus_duration = stimulus_duration / sampling_rate
	max_amplitude = Get absolute extremum: 0, 0, "none"
	Save as WAV file: output_folder$ + file$ + ".wav"

	## export repetitions
	selectObject: log
	rep = Get value: n, "rep"
	for ex from 1 to n_export
		if rep = export# [ex]
			createFolder: output_folder$ + "stims_" + string$(rep)
			selectObject: stimulus
			Save as WAV file: output_folder$ + "stims_" + string$(rep) + "/" + file$ + ".wav"

			selectObject: export_table# [ex]
			Append row
			n_rows = Get number of rows
			Set string value: n_rows, "sound_file_name", file$ + ".wav"
			Set numeric value: n_rows, "sound_duration", stimulus_duration
		endif
	endfor

	removeObject: stimulus

	selectObject: log
	Set numeric value: n, "word_ms", round(word_duration * 1000)
	Set numeric value: n, "file_ms", round(stimulus_duration * 1000)
	Set numeric value: n, "clipped", max_amplitude > 1
	Set string value: n, "note", note$

	appendInfo: file$, tab$, fixed$(stimulus_duration * 1000, 0), " ms"
	if max_amplitude > 1
		appendInfo: tab$, "WARNING: clipped (max ", fixed$(max_amplitude, 2), ")"
	endif
	appendInfoLine: ""
endfor

## save as UTF-8 (not UTF-16), then restore the default
selectObject: log
Text writing preferences: "UTF-8"
Save as comma-separated file: output_folder$ + sound_name$ + "_log.csv"
export_info$ = ""
for ex from 1 to n_export
	selectObject: export_table# [ex]
	n_rows = Get number of rows
	if n_rows > 0
		Save as comma-separated file: output_folder$ + "sf_dur_" + string$(export# [ex]) + ".csv"
		export_info$ = export_info$ + "Copied " + string$(n_rows) + " files of repetition " + string$(export# [ex])
		... + " into stims_" + string$(export# [ex]) + " (durations in sf_dur_" + string$(export# [ex]) + ".csv)" + newline$
	else
		export_info$ = export_info$ + "WARNING: no word has a repetition " + string$(export# [ex])
		... + " - no stims_" + string$(export# [ex]) + " folder made." + newline$
	endif
	removeObject: export_table# [ex]
endfor
Text writing preferences: "try ISO Latin-1, then UTF-16"

removeObject: table, log, intensity
appendInfoLine: newline$, "Saved ", n_stimuli, " stimuli and ", sound_name$, "_log.csv to ", output_folder$
appendInfo: export_info$
if n_stimuli <> n_expected
	appendInfoLine: "WARNING: expected ", n_expected, " stimuli but ", n_stimuli, " files were saved."
endif

###############################################################
## procedures

## number of files and subfolders (creates the folder if missing)
procedure countFiles: .folder$
	createFolder: .folder$
	.files = Create Strings as file list: "files", .folder$ + "/*"
	.n_files = Get number of strings
	.folders = Create Strings as folder list: "folders", .folder$ + "/*"
	.n_folders = Get number of strings
	removeObject: .files, .folders
	.n = .n_files + .n_folders
endproc

procedure askOutputFolder: .n_files, .folder$
	beginPause: "Output folder already in use"
		comment: "This folder already contains " + string$(.n_files) + " files or folders from an earlier run:"
		comment: "     " + .folder$
		comment: ""
		comment: "Overwrite: save into this folder anyway."
		comment: "     Files with the same names are replaced, all other old files stay."
		comment: "New folder: save into " + sound_name$ + "_2 (or _3, ...) instead."
	.clicked = endPause: "Stop", "Overwrite", "New folder", 3, 1
	if .clicked = 1
		exitScript: "Stopped by user."
	endif
endproc

## opens the editor until the word count matches (first pass: and no stray text)
procedure fixCount: .first_pass
	.done = 0
	while .done = 0
		@checkTextGrid: .first_pass

		if checkTextGrid.n_words = n_expected and checkTextGrid.n_stray = 0
			.done = 1
		else
			if checkTextGrid.n_words = n_expected
				.text$ = "Found " + string$(checkTextGrid.n_words) + " word intervals (matches the csv)," + newline$
				... + "but some silences carry stray text." + newline$
			else
				.text$ = "Found " + string$(checkTextGrid.n_words) + " word intervals, but expected " + string$(n_expected) + newline$
				... + "(" + string$(stimuli_nrows) + " csv rows x " + string$(repetitions_per_word) + " repetitions)." + newline$
			endif
			.text$ = .text$ + newline$
			... + checkTextGrid.summary$ + newline$
			... + newline$
			... + "Silences are labelled " + silent_label$ + ", words are left empty." + newline$
			... + "The guide tier (tier 2) numbers the words and shows the expected csv word." + newline$
			... + "     It is only a guide - it is rebuilt on every check." + newline$
			... + newline$
			... + "Click Recheck after editing." + newline$
			... + "Please don't close the editor window yourself."

			if checkTextGrid.n_stray > 0
				@pauseEditor: "TextGrid needs fixing", .text$, "Stop", "Recheck", "Stray text = silence"
				if pauseEditor.clicked = 3
					@straysToSilence
				endif
			else
				@pauseEditor: "TextGrid needs fixing", .text$, "Stop", "Recheck", ""
			endif
		endif
	endwhile
	appendInfoLine: "Word count matches the csv (", n_expected, " words)."
endproc

procedure slotLabels
	selectObject: textgrid
	.n_intervals = Get number of intervals: 1
	.k = 0

	for m from 1 to .n_intervals
		selectObject: textgrid
		intvl_lbl$ = Get label of interval: 1, m

		if intvl_lbl$ <> silent_label$
			.k += 1
			selectObject: table
			stimuli_value$ = Get value: ceiling(.k / repetitions_per_word), stimuli_column$

			selectObject: textgrid
			Set interval text: 1, m, stimuli_value$
		endif
	endfor
endproc

## counts words and stray text, flags SHORT / LONG / SHIFT, rebuilds the guide tier
procedure checkTextGrid: .first_pass
	clearinfo
	appendInfo: setup_info$
	appendInfoLine: newline$, "--- check ---"

	selectObject: textgrid
	.n_intervals = Get number of intervals: 1
	word_start# = zero# (.n_intervals)
	word_end# = zero# (.n_intervals)
	.n_words = 0
	.n_stray = 0
	.first_stray$ = ""

	for m from 1 to .n_intervals
		intvl_lbl$ = Get label of interval: 1, m
		if intvl_lbl$ <> silent_label$
			intvl_start = Get start time of interval: 1, m
			if .first_pass and intvl_lbl$ <> ""
				.n_stray += 1
				appendInfoLine: "STRAY TEXT on interval ", m, " at ", fixed$(intvl_start, 2), " s: """, intvl_lbl$, """"
				if .n_stray = 1
					.first_stray$ = "interval " + string$(m) + " at " + fixed$(intvl_start, 1) + " s"
				endif
			else
				.n_words += 1
				word_start# [.n_words] = intvl_start
				word_end# [.n_words] = Get end time of interval: 1, m
			endif
		endif
	endfor

	@checkRepetitions: .n_words

	## rebuild the guide tier
	n_tiers = Get number of tiers
	if n_tiers > 1
		Remove tier: 2
	endif
	Duplicate tier: 1, 2, "guide"

	.n_short = 0
	.n_long = 0
	.first_short$ = ""
	.first_long$ = ""
	.k = 0

	for m from 1 to .n_intervals
		selectObject: textgrid
		intvl_lbl$ = Get label of interval: 2, m

		if intvl_lbl$ = silent_label$
			Set interval text: 2, m, ""
		elsif .first_pass and intvl_lbl$ <> ""
			Set interval text: 2, m, "STRAY"
		else
			.k += 1
			.duration_ms = (word_end# [.k] - word_start# [.k]) * 1000
			.flags$ = ""
			if .duration_ms < short_interval
				.flags$ = .flags$ + " SHORT"
				.n_short += 1
				appendInfoLine: "SHORT word #", .k, " at ", fixed$(word_start# [.k], 2), " s (", fixed$(.duration_ms, 0), " ms)"
				if .n_short = 1
					.first_short$ = "#" + string$(.k) + " at " + fixed$(word_start# [.k], 1) + " s"
				endif
			elsif .duration_ms > long_interval
				.flags$ = .flags$ + " LONG"
				.n_long += 1
				appendInfoLine: "LONG word #", .k, " at ", fixed$(word_start# [.k], 2), " s (", fixed$(.duration_ms, 0), " ms)"
				if .n_long = 1
					.first_long$ = "#" + string$(.k) + " at " + fixed$(word_start# [.k], 1) + " s"
				endif
			endif
			if checkRepetitions.done
				if .k <= checkRepetitions.n
					if shift# [.k] <> 0
						.flags$ = .flags$ + " SHIFT" + if shift# [.k] > 0 then "+" else "" fi + string$(shift# [.k])
					endif
				endif
			endif

			if .k <= n_expected
				selectObject: table
				stimuli_value$ = Get value: ceiling(.k / repetitions_per_word), stimuli_column$
			else
				stimuli_value$ = "(extra)"
			endif
			selectObject: textgrid
			Set interval text: 2, m, string$(.k) + " " + stimuli_value$ + .flags$
		endif
	endfor

	## summary for the pause windows
	.summary$ = ""
	if .n_stray > 0
		.summary$ = .summary$ + "     " + string$(.n_stray) + " silent intervals carry stray text (first: " + .first_stray$ + ")" + newline$
	endif
	if .n_short > 0
		.summary$ = .summary$ + "     " + string$(.n_short) + " SHORT words (first: " + .first_short$ + ")" + newline$
	endif
	if .n_long > 0
		.summary$ = .summary$ + "     " + string$(.n_long) + " LONG words (first: " + .first_long$ + ")" + newline$
	endif
	if checkRepetitions.n_stretches > 0
		.summary$ = .summary$ + "     " + string$(checkRepetitions.n_stretches) + " possible SHIFT stretches (first: "
		... + checkRepetitions.first_stretch$ + ")" + newline$
	endif
	if .summary$ = ""
		.summary$ = "No problems flagged."
	else
		.summary$ = "Warnings (also marked on the guide tier):" + newline$ + .summary$
		... + "     The full list with times is in the Info window."
	endif
endproc

## pauses between different words are longer than between repetitions: per 30-word window,
## test whether csv shifts of -2..+2 fit the pauses better.
## shift# [k]: 0 = fine, -1 = extra interval before k, +1 = missing / merged word
procedure checkRepetitions: .n_words
	.n = min(.n_words, n_expected)
	.done = 0
	.n_stretches = 0
	.first_stretch$ = ""
	.window = 30

	.n_changes = 0
	for k from 2 to .n
		.n_changes += change# [k]
	endfor

	if check_repetition_pattern and .n >= .window and .n_changes > 0 and .n_changes < .n - 1
		.done = 1
		shift# = zero# (.n)
		gap# = zero# (.n)
		for k from 2 to .n
			gap# [k] = word_start# [k] - word_end# [k - 1]
		endfor

		.lo = 2
		while .lo + .window - 1 <= .n
			.hi = .lo + .window - 1

			window_gap# = zero# (.window)
			for k from .lo to .hi
				window_gap# [k - .lo + 1] = gap# [k]
			endfor
			window_gap# = sort# (window_gap#)
			.median = window_gap# [.window / 2]

			## fraction of pauses that agree with the shifted word changes
			.best_shift = 0
			.best_score = -1
			.score_0 = 0
			for s from -2 to 2
				.agree = 0
				.total = 0
				for k from .lo to .hi
					if k + s >= 2 and k + s <= .n
						.total += 1
						if change# [k + s] = (gap# [k] > .median)
							.agree += 1
						endif
					endif
				endfor
				.score = .agree / .total
				if s = 0
					.score_0 = .score
				endif
				if .score > .best_score
					.best_score = .score
					.best_shift = s
				endif
			endfor

			if .best_shift <> 0 and .best_score - .score_0 >= 0.15
				for k from .lo to .hi
					if shift# [k] = 0
						shift# [k] = .best_shift
					endif
				endfor
			endif
			.lo += .window / 2
		endwhile

		## report stretches with the same shift
		.k = 1
		while .k <= .n
			if shift# [.k] <> 0
				.stretch_end = .k
				while .stretch_end < .n and shift# [.stretch_end + 1] = shift# [.k]
					.stretch_end += 1
				endwhile
				.n_stretches += 1
				.description$ = "#" + string$(.k) + "-#" + string$(.stretch_end) + " (" + fixed$(word_start# [.k], 0)
				... + "-" + fixed$(word_end# [.stretch_end], 0) + " s)"
				appendInfoLine: "SHIFT words ", .description$, ": the pauses fit the csv better shifted by ", shift# [.k],
				... " (-1 = probably an extra interval near the start of this stretch, +1 = a missing / merged word)"
				if .n_stretches = 1
					.first_stretch$ = .description$
				endif
				.k = .stretch_end + 1
			else
				.k += 1
			endif
		endwhile
	endif
endproc

## silence detection -> seg_start# / seg_end# (seg_n words), then merge and widen.
## Words starting after .t_max are skipped; the median word duration uses all words
procedure segment: .threshold, .min_silent, .min_sounding, .merge, .widen, .t_max
	selectObject: intensity
	.tg = To TextGrid (silences): .threshold, .min_silent, .min_sounding, silent_label$, "w"
	.table = Down to Table: "no", 10, "no", "no"
	.words = Extract rows where column (text): "text", "is equal to", "w"
	.n_all = Get number of rows
	.median = 0
	if .n_all > 0
		Append column: "dur"
		Formula: "dur", "self [""tmax""] - self [""tmin""]"
		.median = Get quantile: "dur", 0.5
	endif
	seg_n = 0
	seg_start# = zero# (max (1, .n_all))
	seg_end# = zero# (max (1, .n_all))
	.w = 1
	while .w <= .n_all
		.t = Get value: .w, "tmin"
		if .t > .t_max
			.w = .n_all
		else
			seg_n += 1
			seg_start# [seg_n] = .t
			seg_end# [seg_n] = Get value: .w, "tmax"
		endif
		.w += 1
	endwhile
	removeObject: .tg, .table, .words
	.n_merged = 0
	if .merge and seg_n > 1
		@mergeSplitWords: .median
		.n_merged = mergeSplitWords.n_merged
	endif
	if .widen and seg_n > 0
		@widenEdges
	endif
endproc

## joins words across pauses < merge_max_pause, shortest first, while the result is
## at most merge_max_ratio x the median word duration (a word split at a stop closure)
procedure mergeSplitWords: .median
	.gaps = Create Table with column names: "gaps", seg_n - 1, "k gap"
	for .k from 1 to seg_n - 1
		Set numeric value: .k, "k", .k
		Set numeric value: .k, "gap", seg_start# [.k + 1] - seg_end# [.k]
	endfor
	Sort rows: "gap k"
	## .left# [last word of a run] = first word of the run, .right# [first word] = last word
	.left# = zero# (seg_n)
	.right# = zero# (seg_n)
	.joined# = zero# (seg_n)
	for .w from 1 to seg_n
		.left# [.w] = .w
		.right# [.w] = .w
	endfor
	.n_merged = 0
	.row = 1
	while .row <= seg_n - 1
		.gap = Get value: .row, "gap"
		if .gap >= merge_max_pause
			.row = seg_n
		else
			.k = Get value: .row, "k"
			.l = .left# [.k]
			.r = .right# [.k + 1]
			if seg_end# [.r] - seg_start# [.l] <= merge_max_ratio * .median
				.joined# [.k] = 1
				.right# [.l] = .r
				.left# [.r] = .l
				.n_merged += 1
			endif
			.row += 1
		endif
	endwhile
	removeObject: .gaps
	## keep the outer edges of each joined run
	.n = 0
	for .w from 1 to seg_n
		if .w = 1
			.n += 1
			seg_start# [.n] = seg_start# [.w]
		elsif .joined# [.w - 1] = 0
			.n += 1
			seg_start# [.n] = seg_start# [.w]
		endif
		seg_end# [.n] = seg_end# [.w]
	endfor
	seg_n = .n
endproc

## widens each word while the intensity is above edge_threshold (and noise floor + 6 dB),
## by at most edge_max, never past the middle of the pause
procedure widenEdges
	.limit = intensity_max + max (edge_threshold, noise_floor + 6)
	.new_start# = seg_start#
	.new_end# = seg_end#
	for .w from 1 to seg_n
		.lo = max (0, seg_start# [.w] - edge_max)
		if .w > 1
			.lo = max (.lo, (seg_end# [.w - 1] + seg_start# [.w]) / 2)
		endif
		.hi = min (sound_duration, seg_end# [.w] + edge_max)
		if .w < seg_n
			.hi = min (.hi, (seg_end# [.w] + seg_start# [.w + 1]) / 2)
		endif

		.f0 = min (n_frames, max (1, round ((seg_start# [.w] - frame_t1) / frame_dt) + 1))
		.f = .f0
		.go = 1
		while .go
			if .f - 1 < 1
				.go = 0
			elsif frame_t1 + (.f - 2) * frame_dt < .lo
				.go = 0
			elsif intensity## [1, .f - 1] < .limit
				.go = 0
			else
				.f -= 1
			endif
		endwhile
		if .f < .f0
			.new_start# [.w] = min (seg_start# [.w], max (.lo, frame_t1 + (.f - 1) * frame_dt - frame_dt / 2))
		endif

		.g0 = min (n_frames, max (1, round ((seg_end# [.w] - frame_t1) / frame_dt) + 1))
		.g = .g0
		.go = 1
		while .go
			if .g + 1 > n_frames
				.go = 0
			elsif frame_t1 + .g * frame_dt > .hi
				.go = 0
			elsif intensity## [1, .g + 1] < .limit
				.go = 0
			else
				.g += 1
			endif
		endwhile
		if .g > .g0
			.new_end# [.w] = max (seg_end# [.w], min (.hi, frame_t1 + (.g - 1) * frame_dt + frame_dt / 2))
		endif
	endfor
	seg_start# = .new_start#
	seg_end# = .new_end#
endproc

## TextGrid from seg_start# / seg_end#: words empty, the rest silent_label$
procedure makeTextGrid
	textgrid = Create TextGrid: 0, sound_duration, "silences", ""
	Rename: sound_name$
	.last = 0
	for .w from 1 to seg_n
		if seg_start# [.w] > .last and seg_start# [.w] < sound_duration
			Insert boundary: 1, seg_start# [.w]
		endif
		if seg_end# [.w] < sound_duration
			Insert boundary: 1, seg_end# [.w]
		endif
		.last = seg_end# [.w]
	endfor
	.n_intervals = Get number of intervals: 1
	for .m from 1 to .n_intervals
		Set interval text: 1, .m, silent_label$
	endfor
	for .w from 1 to seg_n
		.m = Get interval at time: 1, (seg_start# [.w] + seg_end# [.w]) / 2
		Set interval text: 1, .m, ""
	endfor
endproc

## warns when the threshold is within 10 dB of the noise floor
procedure checkNoiseFloor
	setup_info$ = setup_info$ + "Noise floor (10th percentile of the intensity): " + fixed$(noise_floor, 1) + " dB re. maximum." + newline$
	if silence_threshold < noise_floor + 10
		setup_info$ = setup_info$ + "WARNING: the silence threshold (" + fixed$(silence_threshold, 1)
		... + " dB) is less than 10 dB above the noise floor - pauses may be missed and words merged." + newline$
		... + "     Try a higher threshold (e.g. " + fixed$(noise_floor + 15, 0) + " dB), or tune settings." + newline$
	endif
endproc

## the user corrects a stretch at the start; candidate settings are scored on it and the best
## replace the current ones only if they need at least 3 and 30% fewer corrections
procedure tuneSettings
	@segment: silence_threshold, minimum_silent_interval, minimum_sounding_interval, merge_split_words, widen_edges, sound_duration
	@makeTextGrid

	## stretch ends mid-pause after first word + tuning_stretch_s
	.t_end = sound_duration
	if seg_n > 1
		.target = seg_start# [1] + tuning_stretch_s
		.w = 1
		while .w < seg_n
			if seg_end# [.w] >= .target
				.t_end = (seg_end# [.w] + seg_start# [.w + 1]) / 2
				.w = seg_n
			endif
			.w += 1
		endwhile
	endif
	selectObject: textgrid
	Insert interval tier: 2, "tuning"
	if .t_end < sound_duration
		Insert boundary: 2, .t_end
	endif
	Set interval text: 2, 1, "CORRECT THIS STRETCH"

	.text$ = "Optional first step: tune the segmentation settings." + newline$
	... + newline$
	... + "Please correct the stretch marked on the tuning tier (0 - " + fixed$(.t_end, 1) + " s):" + newline$
	... + "     every list word in its own interval, left empty," + newline$
	... + "     everything else (pauses, talk, coughs, restarts, extra words) labelled " + silent_label$ + "." + newline$
	... + "     Split words joined back, joined words split, boundaries at the word edges." + newline$
	... + "     You can move the end of the stretch on the tuning tier." + newline$
	... + newline$
	... + "The script then tries 150 segmentation settings on this stretch, and switches to the" + newline$
	... + "     best ones only if they clearly beat the current settings." + newline$
	... + "     Your corrections of the stretch are kept." + newline$
	... + newline$
	... + "Please don't close the editor window yourself."
	@pauseEditor: "Tune settings: correct the stretch", .text$, "Stop", "Skip tuning", "Test settings"

	if pauseEditor.clicked = 2
		removeObject: textgrid
		setup_info$ = setup_info$ + "Tuning skipped." + newline$
	else
		## stretch end as set by the user
		selectObject: textgrid
		.n_tiers = Get number of tiers
		if .n_tiers > 1
			.tier2$ = Get tier name: 2
			if .tier2$ = "tuning"
				.t_end = Get end time of interval: 2, 1
			endif
		endif
		.n_intervals = Get number of intervals: 1
		ref_n = 0
		ref_start# = zero# (.n_intervals)
		ref_end# = zero# (.n_intervals)
		for .m from 1 to .n_intervals
			.lbl$ = Get label of interval: 1, .m
			.s = Get start time of interval: 1, .m
			if .lbl$ <> silent_label$ and .s < .t_end
				ref_n += 1
				ref_start# [ref_n] = .s
				ref_end# [ref_n] = Get end time of interval: 1, .m
			endif
		endfor
		removeObject: textgrid

		if ref_n < 10
			setup_info$ = setup_info$ + "WARNING: only " + string$(ref_n) + " words in the tuning stretch - tuning skipped." + newline$
		else
			.results = Create Table with column names: "tuning", 0,
			... "to_fix splits merges missed short_extra long_extra threshold min_silent min_sounding merge current distance"
			## current settings first, then the candidates
			@tuneCandidate: .results, silence_threshold, minimum_silent_interval, minimum_sounding_interval, merge_split_words, .t_end, 1
			.thresholds# = {-20, -25, -30, -35, -40}
			.silents# = {0.15, 0.2, 0.25, 0.3, 0.35}
			.soundings# = {0.05, 0.1, 0.15}
			for .it from 1 to 5
				for .is from 1 to 5
					for .iz from 1 to 3
						for .im from 0 to 1
							@tuneCandidate: .results, .thresholds# [.it], .silents# [.is], .soundings# [.iz], .im, .t_end, 0
						endfor
					endfor
				endfor
			endfor

			selectObject: .results
			Sort rows: "to_fix distance"
			.best_fix = Get value: 1, "to_fix"
			.current_row = Search column: "current", "1"
			.current_fix = Get value: .current_row, "to_fix"
			Save as comma-separated file: output_folder$ + sound_name$ + "_tuning.csv"
			.n_settings = Get number of rows

			.info$ = "Tuning on 0 - " + fixed$(.t_end, 1) + " s (" + string$(ref_n) + " corrected words); corrections the"
			... + " segmentation would need there (splits + merges + missed + short extra intervals):" + newline$
			... + "     current settings: " + string$(.current_fix) + ", best: " + string$(.best_fix)
			... + " (all " + string$(.n_settings) + " settings in " + sound_name$ + "_tuning.csv)" + newline$
			if .current_fix - .best_fix >= max (3, 0.3 * .current_fix)
				silence_threshold = Get value: 1, "threshold"
				minimum_silent_interval = Get value: 1, "min_silent"
				minimum_sounding_interval = Get value: 1, "min_sounding"
				merge_split_words = Get value: 1, "merge"
				.info$ = .info$ + "     -> switched to the best settings." + newline$
			else
				.info$ = .info$ + "     -> kept the current settings (the best ones are not clearly better)." + newline$
			endif
			removeObject: .results
			setup_info$ = setup_info$ + .info$
			keep_stretch = 1
			stretch_end = .t_end
		endif
	endif
endproc

## one tuning row (no widening: it doesn't change the count)
procedure tuneCandidate: .table, .threshold, .min_silent, .min_sounding, .merge, .t_end, .current
	@segment: .threshold, .min_silent, .min_sounding, .merge, 0, .t_end + 5
	@scoreStretch: .t_end
	selectObject: .table
	Append row
	.r = Get number of rows
	Set numeric value: .r, "to_fix", scoreStretch.to_fix
	Set numeric value: .r, "splits", scoreStretch.splits
	Set numeric value: .r, "merges", scoreStretch.merges
	Set numeric value: .r, "missed", scoreStretch.missed
	Set numeric value: .r, "short_extra", scoreStretch.short_extra
	Set numeric value: .r, "long_extra", scoreStretch.long_extra
	Set numeric value: .r, "threshold", .threshold
	Set numeric value: .r, "min_silent", .min_silent
	Set numeric value: .r, "min_sounding", .min_sounding
	Set numeric value: .r, "merge", .merge
	Set numeric value: .r, "current", .current
	Set numeric value: .r, "distance", abs (.threshold - silence_threshold) / 5 + abs (.min_silent - minimum_silent_interval) / 0.05
	... + abs (.min_sounding - minimum_sounding_interval) / 0.05 + abs (.merge - merge_split_words)
endproc

## compares seg_* with the corrected ref_* words; linked if overlap >= min(50 ms, half the shorter).
## Unlinked words >= 0.25 s (long_extra) are extra productions, not counted in to_fix
procedure scoreStretch: .t_end
	.nc = 0
	for .w from 1 to seg_n
		if seg_start# [.w] < .t_end
			.nc = .w
		endif
	endfor
	.links_ref# = zero# (max (1, ref_n))
	.links_c# = zero# (max (1, .nc))
	.j0 = 1
	for .i from 1 to .nc
		.cs = seg_start# [.i]
		.ce = seg_end# [.i]
		.go = 1
		while .go
			if .j0 > ref_n
				.go = 0
			elsif ref_end# [.j0] <= .cs
				.j0 += 1
			else
				.go = 0
			endif
		endwhile
		.j = .j0
		.go = 1
		while .go
			if .j > ref_n
				.go = 0
			elsif ref_start# [.j] >= .ce
				.go = 0
			else
				.ov = min (.ce, ref_end# [.j]) - max (.cs, ref_start# [.j])
				if .ov > 0 and .ov >= min (0.05, 0.5 * min (.ce - .cs, ref_end# [.j] - ref_start# [.j]))
					.links_ref# [.j] += 1
					.links_c# [.i] += 1
				endif
				.j += 1
			endif
		endwhile
	endfor
	.splits = 0
	.missed = 0
	for .j from 1 to ref_n
		.splits += max (0, .links_ref# [.j] - 1)
		.missed += (.links_ref# [.j] = 0)
	endfor
	.merges = 0
	.short_extra = 0
	.long_extra = 0
	for .i from 1 to .nc
		.merges += max (0, .links_c# [.i] - 1)
		if .links_c# [.i] = 0
			if seg_end# [.i] - seg_start# [.i] < 0.25
				.short_extra += 1
			else
				.long_extra += 1
			endif
		endif
	endfor
	.to_fix = .splits + .merges + .missed + .short_extra
endproc

## corrected words in the tuning stretch, new segmentation after it
procedure spliceStretch
	.t_cut = stretch_end
	if ref_n > 0
		.t_cut = max (.t_cut, ref_end# [ref_n])
	endif
	.new_start# = zero# (ref_n + seg_n)
	.new_end# = zero# (ref_n + seg_n)
	for .j from 1 to ref_n
		.new_start# [.j] = ref_start# [.j]
		.new_end# [.j] = ref_end# [.j]
	endfor
	.n = ref_n
	for .w from 1 to seg_n
		if (seg_start# [.w] + seg_end# [.w]) / 2 > .t_cut
			.n += 1
			.new_start# [.n] = max (seg_start# [.w], .t_cut)
			.new_end# [.n] = seg_end# [.w]
		endif
	endfor
	seg_n = .n
	seg_start# = .new_start#
	seg_end# = .new_end#
	setup_info$ = setup_info$ + "Kept your corrected words up to " + fixed$(.t_cut, 1) + " s (" + string$(ref_n) + " words)." + newline$
endproc

## stray labels on tier 1 -> silent_label$
procedure straysToSilence
	selectObject: textgrid
	.n_intervals = Get number of intervals: 1
	for m from 1 to .n_intervals
		intvl_lbl$ = Get label of interval: 1, m
		if intvl_lbl$ <> silent_label$ and intvl_lbl$ <> ""
			Set interval text: 1, m, silent_label$
		endif
	endfor
endproc

## opens the editor and pauses; empty .button3$ is left out, button 1 stops the script
procedure pauseEditor: .title$, .text$, .button1$, .button2$, .button3$
	selectObject: sound, textgrid
	View & Edit

	beginPause: .title$
		.rest$ = .text$
		while .rest$ <> ""
			.cut = index(.rest$, newline$)
			if .cut = 0
				comment: .rest$
				.rest$ = ""
			else
				comment: left$(.rest$, .cut - 1)
				.rest$ = mid$(.rest$, .cut + 1, length(.rest$))
			endif
		endwhile
	if .button3$ = ""
		.clicked = endPause: .button1$, .button2$, 2, 1
	else
		.clicked = endPause: .button1$, .button2$, .button3$, 3, 1
	endif

	nocheck editor: textgrid
		nocheck Close
	endeditor

	if .clicked = 1
		exitScript: "Stopped by user. The Sound and TextGrid are still in the Objects window."
	endif
endproc

## Concatenate follows the Objects list order, not the selection order
procedure joinSounds: .first, .second
	selectObject: .first
	.copy_first = Copy: "first"
	selectObject: .second
	.copy_second = Copy: "second"

	selectObject: .copy_first, .copy_second
	.result = Concatenate
	removeObject: .copy_first, .copy_second
endproc

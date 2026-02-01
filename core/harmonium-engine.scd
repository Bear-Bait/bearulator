/*
BEARULATOR: 32-Band Harmonium Engine v2.1
Inspired by Trevor Treglia's Harmonium (trevortreglia.com)

32-band filterbank additive synthesis with multiple source types,
FM/RM modulation, Buchla LPG simulation, and per-partial animation.

v2.1 ADDITIONS:
- Audio input bus for Vocoder Mode (srcSel 16)
- Track audio routing for processing granular output
- Filterbank frequencies track MIDI for playable vocoder

Architecture: Source → Pre-Sat → BPF Bank (32 bands) → LPG → Output

VOCODER MODE (srcSel 16):
- Receives audio from track grain engines via inBus
- 32-band filterbank shapes the spectral content
- Fundamental frequency (from MIDI) shifts all band centers
- Play the keyboard to "tune" the filterbank to the chaos
*/

// Initialize global params FIRST (before anything else)
~harmoniumParams = IdentityDictionary.new;
~harmoniumParams[\srcSel] = 1;
~harmoniumParams[\formation] = 0;
~harmoniumParams[\fund] = 220;
~harmoniumParams[\amp] = 0.5;
~harmoniumParams[\wet] = 1.0;
~harmoniumParams[\fmEnable] = 0;
~harmoniumParams[\fmTrack] = 0;
~harmoniumParams[\fmHz] = 100;
~harmoniumParams[\fmIndex] = 0.0;
~harmoniumParams[\fmMix] = 0.0;
~harmoniumParams[\fmRatioNum] = 1;
~harmoniumParams[\fmRatioDen] = 1;
~harmoniumParams[\rmEnable] = 0;
~harmoniumParams[\rmTrack] = 0;
~harmoniumParams[\rmHz] = 30;
~harmoniumParams[\rmDepth] = 0.0;
~harmoniumParams[\rmRatioNum] = 1;
~harmoniumParams[\rmRatioDen] = 1;
~harmoniumParams[\lpgMode] = 0;
~harmoniumParams[\envAtk] = 0.005;
~harmoniumParams[\envDec] = 0.15;
~harmoniumParams[\envSus] = 0.7;
~harmoniumParams[\envRel] = 0.25;
~harmoniumParams[\swirlOn] = 1;
~harmoniumParams[\swirlRate] = 0.03;
~harmoniumParams[\swirlDepth] = 0.3;
~harmoniumParams[\smjEnable] = 0;
~harmoniumParams[\smjMax] = 2.0;
~harmoniumParams[\subAmp] = 0.0;
~harmoniumParams[\subOct1] = 0;
~harmoniumParams[\subOct2] = 0;
~harmoniumParams[\num] = 32;
~harmoniumParams[\rq] = 0.02;
~harmoniumParams[\rolloff] = 1.0;
~harmoniumParams[\bandRes] = 0.0;
~harmoniumParams[\timbre] = 0.5;
~harmoniumParams[\preSat] = 0.0;
~harmoniumParams[\bypassBPF] = 0;
~harmoniumParams[\makeup] = 3.0;
~harmoniumParams[\lpfHz] = 14000;
~harmoniumParams[\shepRate] = 0.0;
~harmoniumParams[\swarm] = 0.0;
~harmoniumParams[\inBus] = 0;  // Audio input bus for vocoder mode
~harmoniumParams[\inGain] = 1.0;  // Input gain for vocoder
~harmoniumParams[\mask] = [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
~harmoniumParams[\gains] = Array.fill(32, 1.0);

// Voice management
~harmoniumVoices = IdentityDictionary.new;
~harmoniumVoiceOrder = List.new;
~harmoniumMaxPoly = 8;

// Audio bus for track routing (vocoder input)
~harmoniumInputBus = nil;

SynthDef(\bearulatorHarmonium, { |out = 0,
	gate = 0, freeOnDone = 0,
	fund = 220, noteRatio = 1.0, amp = 0.5, wet = 1.0,
	srcSel = 1, pulseWidth = 0.5, timbre = 0.5, preSat = 0.0,
	num = 32, formation = 0, ouMode = 0,
	rq = 0.02, rolloff = 1.0, bandRes = 0.0, bypassBPF = 0,
	fmEnable = 0, fmTrack = 0, fmHz = 100, fmIndex = 0.0, fmMix = 0.0,
	fmRatioNum = 1, fmRatioDen = 1,
	rmEnable = 0, rmTrack = 0, rmHz = 30, rmDepth = 0.0,
	rmRatioNum = 1, rmRatioDen = 1,
	lpgMode = 0, lpgColor = 0.5,
	envAtk = 0.005, envDec = 0.15, envSus = 0.7, envRel = 0.25,
	swirlOn = 1, swirlRate = 0.03, swirlDepth = 0.3,
	smjEnable = 0, smjMax = 2.0,
	subAmp = 0.0, subOct1 = 0, subOct2 = 0,
	makeup = 3.0, compThresh = 0.25, lpfHz = 14000, ceiling = 0.98,
	shepRate = 0.0, swarm = 0.0,
	inBus = 0, inGain = 1.0,  // Audio input for vocoder mode
	mask = #[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
	gains = #[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
	modSlew = 0.03 |

	// === ALL VARIABLES DECLARED AT TOP ===
	var maxP, inds, nyq, rampTime, fundEff;
	var freqsOver, freqsUnder, useUnder, bankHarm;
	var barkArr, buchArr, freqs;
	var userMask, numMask, valid, actMask;
	var ampWeights, ampWG;
	var saw, pulse, sine, tri, white, pink, spec, ks;
	var harmFreqs, keep, harmOsc;
	var gendy1, gendy2, gendy3, lorenz;
	var shepSrc, swarmSrc, src, srcMono;
	var inputSrc;  // Audio input source for vocoder
	var timbreCtl, darkSrc, brightSrc, procSrc;
	var fmRatioNumInt, fmRatioDenInt, fmScale, fmFreq, fmMod, fmCar;
	var rmRatioNumInt, rmRatioDenInt, rmScale, rmFreq, ringOsc, ringSig;
	var envGen;
	var swirlWalk, swirlDepthSm, panMod;
	var tChange, tOn, tElapsed, smjDelays, smjGates, smjMask;
	var qmul, rqSafe, resGain, bands, wetSig, drySig;
	var mode, color, cutoff, cutoffMul, lpgSig, pre, dist, lpgOut;
	var subSig, sig, lpfCut;

	// === CONSTANTS ===
	maxP = 32;
	inds = (1..maxP);
	nyq = SampleRate.ir * 0.5;
	rampTime = 0.05;

	// === FUNDAMENTAL FREQUENCY (MIDI-TRACKED) ===
	// This is the key for vocoder mode: noteRatio shifts all 32 band frequencies
	fundEff = fund.max(0.01) * noteRatio.max(0.001);

	// === FREQUENCY ARRAYS (Formation modes) ===
	// These frequencies ALL scale with fundEff, so MIDI input shifts the entire filterbank
	freqsOver = fundEff * inds;
	freqsUnder = fundEff / inds;
	useUnder = (ouMode > 0.5);
	bankHarm = ((1 - useUnder) * freqsOver) + (useUnder * freqsUnder);

	// Bark scale (psychoacoustic critical bands) - scaled by fundEff ratio
	barkArr = #[60,150,250,350,450,570,700,840,1000,1170,1370,1600,1850,2150,2500,2900,3400,4000,4800,5800,7000,8500,10500,13500,0,0,0,0,0,0,0,0];

	// Buchla 200 series frequencies
	buchArr = #[88,125,190,285,430,650,1000,1500,2200,3300,4800,7200,10000,13500,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];

	// Select formation
	freqs = Array.fill(maxP, { |i|
		Select.kr(formation.clip(0, 2), [bankHarm[i], barkArr[i], buchArr[i]])
	});

	// === MASKING ===
	userMask = Lag.kr(mask.clip(0, 1), modSlew);
	numMask = (inds <= num);
	valid = (freqs >= 20) * (freqs <= (nyq * 0.9));
	actMask = Lag.kr(userMask * numMask * valid, modSlew);

	// Amplitude weights (rolloff)
	ampWeights = inds.asFloat.pow(rolloff.neg);
	ampWG = Array.fill(maxP, { |i| ampWeights[i] * gains[i] });

	// === SOURCE GENERATORS ===
	saw = VarSaw.ar(fundEff, 0, 0.5);
	pulse = Pulse.ar(fundEff, pulseWidth.clip(0.01, 0.99));
	sine = SinOsc.ar(fundEff);
	tri = LFTri.ar(fundEff);
	white = WhiteNoise.ar;
	pink = PinkNoise.ar;

	// Spectral noise (formant-like)
	spec = BPF.ar(WhiteNoise.ar, fundEff * [0.5, 1, 2, 3], 0.1).sum * 0.3;

	// Karplus-Strong
	ks = Pluck.ar(
		WhiteNoise.ar(0.5),
		Trig1.kr(gate, 0.001),
		1.0 / fundEff.max(20),
		1.0 / fundEff.max(20),
		4.0, 0.3
	);

	// Harmonic oscillator (additive sine bank)
	harmFreqs = fundEff * inds;
	keep = harmFreqs <= nyq;
	harmOsc = Mix.ar(SinOsc.ar(harmFreqs, 0, keep)) * (1.0 / maxP);

	// Gendy (stochastic)
	gendy1 = Gendy1.ar;
	gendy2 = Gendy2.ar;
	gendy3 = Gendy3.ar;

	// Lorenz attractor
	lorenz = LorenzL.ar(freq: 50, s: 10, r: 28, b: 2.667);

	// Shepard tone (infinite rising/falling)
	shepSrc = Mix.fill(10, { |n|
		var phase, localPhase, freq, ampEnv;
		phase = Phasor.kr(0, shepRate * SampleDur.ir, 0, 1, 0);
		localPhase = (phase + (n / 10)).wrap(0, 1);
		freq = fundEff * (2 ** ((localPhase - 0.5) * 4));
		ampEnv = (((localPhase - 0.5) / 0.2).squared * (-0.5)).exp;
		SinOsc.ar(freq) * ampEnv;
	}) * 0.1;

	// Swarm (detuned chorus cloud)
	swarmSrc = Mix.fill(8, { |n|
		var oct, baseFreq, rateJitter, rate, phase, ampEnv, detLFO, detAmt, detSemis, detune, freq, speed;
		speed = (shepRate.abs * 6).max(0.1);
		oct = n - 3.5;
		baseFreq = fundEff * (2 ** oct);
		rateJitter = 1 + (LFNoise1.kr(0.1 * (n + 1) * speed) * swarm * 4);
		rate = shepRate * rateJitter;
		phase = Phasor.kr(0, rate * SampleDur.ir, 0, 1, 0);
		ampEnv = (((phase - 0.5) / 0.25).squared * (-0.5)).exp;
		detLFO = LFNoise1.kr(0.15 * (n + 1) * speed);
		detAmt = swarm * 12;
		detSemis = (detLFO * detAmt).clip2(12);
		detune = detSemis.midiratio;
		freq = baseFreq * detune;
		SinOsc.ar(freq) * ampEnv;
	}) * 0.75;

	// === AUDIO INPUT (VOCODER MODE - srcSel 16) ===
	// Reads stereo from inBus (track output) and sums to mono
	inputSrc = Mix.ar(In.ar(inBus, 2)) * 0.5 * inGain.lag(rampTime);

	// Source selection (0-18)
	// Source 16 is now "Track Audio" for vocoder mode
	src = SelectX.ar(VarLag.kr(srcSel.clip(0, 18), 0.02), [
		Silent.ar(1),   // 0: Silence
		sine,           // 1: Sine
		tri,            // 2: Triangle
		saw,            // 3: Saw
		pulse,          // 4: Pulse
		white,          // 5: White noise
		pink,           // 6: Pink noise
		spec,           // 7: Spectral
		ks,             // 8: Karplus-Strong
		harmOsc,        // 9: Harmonic
		gendy1,         // 10: Gendy1
		gendy2,         // 11: Gendy2
		gendy3,         // 12: Gendy3
		lorenz,         // 13: Lorenz
		Silent.ar(1),   // 14: Sample (placeholder)
		Silent.ar(1),   // 15: Feedback (placeholder)
		inputSrc,       // 16: TRACK AUDIO (Vocoder Mode!)
		shepSrc,        // 17: Shepard
		swarmSrc        // 18: Swarm
	]);

	// Pre-saturation
	srcMono = LeakDC.ar((src * (1 + preSat.max(0))).tanh);

	// Timbre control (dark/bright crossfade)
	timbreCtl = timbre.clip(0, 1);
	darkSrc = LPF.ar(srcMono, timbreCtl.exprange(800, 4000));
	brightSrc = (HPF.ar(srcMono, timbreCtl.exprange(200, 4000)) * timbreCtl.linlin(0, 1, 1, 3)).tanh;
	procSrc = XFade2.ar(darkSrc, brightSrc, timbreCtl.linlin(0, 1, -1, 1));

	// === FM MODULATION ===
	fmRatioNumInt = fmRatioNum.clip(1, 64).round(1);
	fmRatioDenInt = fmRatioDen.clip(1, 64).round(1);
	fmScale = fmRatioNumInt / fmRatioDenInt;
	fmFreq = ((1 - VarLag.kr(fmTrack.clip(0, 1), 0.02)) * fmHz.clip(0.1, 20000))
		+ (VarLag.kr(fmTrack.clip(0, 1), 0.02) * (fundEff * fmScale).clip(0.1, 20000));
	fmMod = SinOsc.ar(fmFreq);
	fmCar = FreqShift.ar(procSrc, fmMod * fmIndex.lag(rampTime) * fmFreq * fmEnable);
	procSrc = XFade2.ar(procSrc, fmCar, (fmMix.lag(rampTime) * 2 - 1));

	// === RING MODULATION ===
	rmRatioNumInt = rmRatioNum.clip(1, 64).round(1);
	rmRatioDenInt = rmRatioDen.clip(1, 64).round(1);
	rmScale = rmRatioNumInt / rmRatioDenInt;
	rmFreq = ((1 - VarLag.kr(rmTrack.clip(0, 1), 0.02)) * rmHz.clip(0.1, 20000))
		+ (VarLag.kr(rmTrack.clip(0, 1), 0.02) * (fundEff * rmScale).clip(0.1, 20000));
	ringOsc = SinOsc.ar(rmFreq);
	ringSig = procSrc * ringOsc;
	procSrc = XFade2.ar(procSrc, ringSig, (rmDepth.lag(rampTime) * rmEnable * 2 - 1));

	// === ENVELOPE ===
	envGen = EnvGen.kr(
		Env.adsr(envAtk, envDec, envSus, envRel),
		gate,
		doneAction: 0
	);

	// === SWIRL (per-partial stereo animation) ===
	swirlWalk = Array.fill(maxP, { |i|
		var phaseOffset;
		phaseOffset = (i / maxP) * 2pi;
		SinOsc.kr(
			swirlRate.max(0.0001) * LFNoise2.kr(0.1).range(0.5, 1.5),
			phaseOffset
		)
	});
	swirlDepthSm = VarLag.kr(swirlDepth.clip(0, 1), 0.02);
	panMod = Select.kr(swirlOn.clip(0, 1), [
		Array.fill(maxP, { 0 }),
		swirlWalk * swirlDepthSm
	]);

	// === SMJ (Staggered Modular Jitter) ===
	tChange = Changed.kr(gate);
	tOn = tChange * (gate > 0);
	tElapsed = Sweep.kr(tOn, 1.0);
	smjDelays = Array.fill(maxP, { TRand.kr(0, smjMax.max(0), tOn) });
	smjGates = tElapsed >= smjDelays;
	smjMask = (1 - smjEnable.clip(0, 1)) + (smjEnable.clip(0, 1) * smjGates);

	// === FILTERBANK ===
	// In Vocoder Mode: these 32 bands shape the incoming track audio
	// The band frequencies (freqs) are derived from fundEff, which tracks MIDI
	// So playing keyboard shifts all filter bands = playable vocoder!
	qmul = bandRes.clip(0, 1).exprange(1, 12);
	rqSafe = (rq / qmul).max(0.0001);
	resGain = bandRes.clip(0, 1).exprange(1, 8);

	bands = BPF.ar(procSrc * envGen, freqs, rqSafe) * rqSafe * resGain * actMask * ampWG * smjMask;

	// Sum with per-partial panning
	wetSig = Array.fill(maxP, { |i|
		Pan2.ar(bands[i], panMod[i]);
	}).sum;

	drySig = (procSrc * envGen) ! 2;

	// Bypass filterbank option
	wetSig = Select.ar(bypassBPF.clip(0, 1), [wetSig, drySig]);

	// === LOWPASS GATE (Buchla 292 simulation) ===
	mode = lpgMode.clip(0, 5);
	color = Select.kr(mode, [0.5, 0.0, 0.0, 0.5, 1.0, 0.5]);
	cutoff = envGen.pow(0.6).exprange(80, 12000);
	cutoffMul = Select.kr(mode, [1.0, 1.0, 0.6, 1.0, 1.0, 1.0]);
	cutoff = cutoff * cutoffMul;

	lpgSig = RLPF.ar(wetSig, cutoff, (1 - (0.2 + (color.clip(0, 1) * 0.7))));
	lpgSig = lpgSig * envGen.pow(0.7 + (color.clip(0, 1) * 0.25));

	// Distortion option for mode 5
	pre = lpgSig * 3.0;
	dist = pre.tanh * (1 / 3.0);

	// Select LPG mode output
	lpgOut = Select.ar(mode, [
		XFade2.ar(drySig, wetSig, (wet.clip(0, 1) * 2 - 1)),  // 0: No LPG
		lpgSig, lpgSig, lpgSig, lpgSig,                       // 1-4: LPG variants
		dist                                                   // 5: Distorted
	]);

	// === SUB OSCILLATORS ===
	subSig = 0;
	subSig = subSig + (SinOsc.ar(fundEff * 0.5) * subOct1);
	subSig = subSig + (SinOsc.ar(fundEff * 0.25) * subOct2);
	subSig = subSig * subAmp.lag(rampTime);

	// === DYNAMICS & OUTPUT ===
	sig = lpgOut * makeup;

	// Lowpass filter
	lpfCut = lpfHz.clip(20, nyq - 10);
	sig = LPF.ar(sig, lpfCut);

	// Limiter
	sig = Limiter.ar(LeakDC.ar(sig), ceiling.clip(0.1, 1.0), 0.005);
	sig = HPF.ar(sig, 8);

	// Add sub and dither
	sig = sig + ((subSig * envGen) ! 2);
	sig = sig + (WhiteNoise.ar(1e-8) ! 2);

	// Final output
	sig = sig * amp.lag(rampTime);

	// Auto-free on silence (if freeOnDone)
	FreeSelf.kr(Done.kr(envGen) * freeOnDone);

	Out.ar(out, sig);
}).add;

// === TRACK AUDIO ROUTING FOR VOCODER ===

// Initialize the input bus (stereo, but we'll sum to mono)
~harmoniumInitBus = {
	if(~harmoniumInputBus.isNil, {
		~harmoniumInputBus = Bus.audio(Server.default, 2);
		"[Harmonium] Created input bus: %".format(~harmoniumInputBus.index).postln;
	});
	~harmoniumInputBus;
};

// Route a track's audio to the Harmonium input
// Call this to set up vocoder mode
~harmoniumRouteTrack = { |trackNum|
	var bus;
	bus = ~harmoniumInitBus.();
	~harmoniumParams[\inBus] = bus.index;
	~harmoniumSetParam.(\inBus, bus.index);
	"[Harmonium] Vocoder mode: routing Track % to Harmonium input (bus %)".format(trackNum + 1, bus.index).postln;
	bus;
};

// SynthDef for routing track audio to Harmonium
SynthDef(\harmoniumTrackRouter, { |inBus, outBus, amp = 1.0|
	var sig;
	sig = In.ar(inBus, 2);
	sig = Mix.ar(sig) * amp;  // Sum to mono
	Out.ar(outBus, sig);
}).add;

// Start routing from a track (PRE-FADER HIJACK)
// This redirects the track's synth output directly to Harmonium, bypassing master bus
~harmoniumStartRouting = { |trackNum|
	var harmBus;

	harmBus = ~harmoniumInitBus.();
	~harmoniumParams[\inBus] = harmBus.index;

	if(~trackManager.notNil, {
		// Use track manager's pre-fader hijack
		~trackManager.hijackTrackForVocoder(trackNum, harmBus.index);
		~harmoniumRoutedTrack = trackNum;  // Remember which track is routed
	}, {
		"[Harmonium] Error: Track manager not available for routing".warn;
	});
};

// Stop routing and restore track to normal output
~harmoniumStopRouting = {
	if(~trackManager.notNil and: { ~harmoniumRoutedTrack.notNil }, {
		~trackManager.restoreTrackRouting(~harmoniumRoutedTrack);
		~harmoniumRoutedTrack = nil;
	});
};

// Track which track is currently routed (for cleanup)
~harmoniumRoutedTrack = nil;

// === HELPER: ONE-CALL VOCODER SETUP ===

// Enable vocoder mode with a single call
// Call this AFTER Track N has loaded a sample and started playback
~enableHarmoniumVocoder = { |trackNum = 0, midiNote = 60, velocity = 100|
	var grainSynth;
	
	trackNum = trackNum ? 0;
	midiNote = midiNote ? 60;
	velocity = velocity ? 100;
	
	"[Harmonium] Setting up vocoder mode...".postln;
	
	// Check if grain synth exists
	if(~trackManager.notNil and: { ~trackManager.tracks[trackNum].notNil }, {
		grainSynth = ~trackManager.tracks[trackNum].grainSynth;
		
		if(grainSynth.isNil, {
			"[ERROR] Track % grain synth not initialized!".format(trackNum + 1).warn;
			"[FIX] Load a sample and start playback first:".postln;
			"  ~trackManager.loadSample(%, \"path/to/audio.wav\");".format(trackNum).postln;
			"  ~trackManager.startPlayback(%);".format(trackNum).postln;
			^nil;
		});
		
		// Step 1: Configure vocoder params
		~harmoniumParams[\srcSel] = 16;        // Source 16 = Track audio
		~harmoniumParams[\amp] = 0.6;
		~harmoniumParams[\bypassBPF] = 0;      // Enable 32-band filterbank
		~harmoniumParams[\lpgMode] = 0;        // Bypass LPG for now
		~harmoniumParams[\inGain] = 1.0;
		~harmoniumParams[\wet] = 1.0;
		
		// Step 2: Route track output to vocoder input bus
		~harmoniumStartRouting.(trackNum);
		
		// Step 3: Spawn Harmonium reader synth
		~harmoniumNoteOn.(midiNote, velocity, 0);
		
		"[OK] Vocoder enabled on Track %: reading grain output, filtering through 32-band EQ".format(trackNum + 1).postln;
		"     MIDI note: % (fundamental = %), amp: %".format(midiNote, midiNote.midicps.round(0.1), ~harmoniumParams[\amp]).postln;
		"     To disable: ~disableHarmoniumVocoder.()".postln;
		
	}, {
		"[ERROR] Track manager not available".warn;
		^nil;
	});
};

// Disable vocoder and restore normal routing
~disableHarmoniumVocoder = {
	if(~harmoniumRoutedTrack.notNil, {
		~harmoniumNoteOff.(60, 0);  // Kill the reader synth
		~harmoniumStopRouting.();    // Restore track routing
		"[OK] Vocoder disabled. Track % restored to normal output.".format(~harmoniumRoutedTrack + 1).postln;
	}, {
		"[INFO] Vocoder not currently enabled".postln;
	});
};

// === POLYPHONIC NOTE FUNCTIONS ===

// Play a polyphonic note
~harmoniumNoteOn = { |note, vel = 100, chan = 0|
	var key, ratio, synth, stealKey, steal;
	var scalarArgs, arrayArgs;

	key = (chan.asString ++ ":" ++ note.asString).asSymbol;
	ratio = (note - 60).midiratio;

	// Voice stealing
	if(~harmoniumVoices.size >= ~harmoniumMaxPoly, {
		stealKey = ~harmoniumVoiceOrder.removeAt(0);
		steal = ~harmoniumVoices.removeAt(stealKey);
		if(steal.notNil, { steal.set(\gate, 0) });
	});

	// Build args list - separate scalar from array params
	// Arrays (mask, gains) must be passed via setn after synth creation
	scalarArgs = [
		\out, 0,  // Always output to speakers
		\srcSel, ~harmoniumParams[\srcSel] ? 1,
		\fund, ~harmoniumParams[\fund] ? 220,
		\amp, ~harmoniumParams[\amp] ? 0.5,
		\wet, ~harmoniumParams[\wet] ? 1.0,
		\formation, ~harmoniumParams[\formation] ? 0,
		\num, ~harmoniumParams[\num] ? 32,
		\rq, ~harmoniumParams[\rq] ? 0.02,
		\rolloff, ~harmoniumParams[\rolloff] ? 1.0,
		\bandRes, ~harmoniumParams[\bandRes] ? 0.0,
		\timbre, ~harmoniumParams[\timbre] ? 0.5,
		\preSat, ~harmoniumParams[\preSat] ? 0.0,
		\bypassBPF, ~harmoniumParams[\bypassBPF] ? 0,
		\makeup, ~harmoniumParams[\makeup] ? 3.0,
		\lpfHz, ~harmoniumParams[\lpfHz] ? 14000,
		\envAtk, ~harmoniumParams[\envAtk] ? 0.005,
		\envDec, ~harmoniumParams[\envDec] ? 0.15,
		\envSus, ~harmoniumParams[\envSus] ? 0.7,
		\envRel, ~harmoniumParams[\envRel] ? 0.25,
		\swirlOn, ~harmoniumParams[\swirlOn] ? 1,
		\swirlRate, ~harmoniumParams[\swirlRate] ? 0.03,
		\swirlDepth, ~harmoniumParams[\swirlDepth] ? 0.3,
		\fmEnable, ~harmoniumParams[\fmEnable] ? 0,
		\rmEnable, ~harmoniumParams[\rmEnable] ? 0,
		\lpgMode, ~harmoniumParams[\lpgMode] ? 0,
		\smjEnable, ~harmoniumParams[\smjEnable] ? 0,
		\subAmp, ~harmoniumParams[\subAmp] ? 0.0,
		\inBus, ~harmoniumParams[\inBus] ? 0,
		\inGain, ~harmoniumParams[\inGain] ? 1.0
	];

	"[Harmonium] Creating synth with srcSel=%, amp=%, out=0".format(
		~harmoniumParams[\srcSel], ~harmoniumParams[\amp]
	).postln;

	// Create synth with explicit args
	synth = Synth(\bearulatorHarmonium,
		scalarArgs ++ [
			\noteRatio, ratio,
			\gate, 1,
			\freeOnDone, 1
		]
	);

	// Now set the array parameters
	synth.setn(\mask, ~harmoniumParams[\mask]);
	synth.setn(\gains, ~harmoniumParams[\gains]);

	"[Harmonium] Note ON: % (synth: %)".format(note, synth).postln;

	synth.onFree({
		{ ~harmoniumVoices.removeAt(key); ~harmoniumVoiceOrder.remove(key) }.defer
	});

	~harmoniumVoices[key] = synth;
	~harmoniumVoiceOrder.add(key);
};

// Release a note
~harmoniumNoteOff = { |note, chan = 0|
	var key, synth;

	key = (chan.asString ++ ":" ++ note.asString).asSymbol;
	synth = ~harmoniumVoices.removeAt(key);
	~harmoniumVoiceOrder.remove(key);
	if(synth.notNil, { synth.set(\gate, 0) });
};

// Update all voices
~harmoniumSetParam = { |param, value|
	~harmoniumParams[param] = value;
	if(param == \mask or: { param == \gains }, {
		~harmoniumVoices.values.do({ |s| s.setn(param, value) });
	}, {
		~harmoniumVoices.values.do({ |s| s.set(param, value) });
	});
};

// Panic - kill all voices
~harmoniumPanic = {
	~harmoniumVoices.values.do({ |s| s.set(\gate, 0) });
	~harmoniumVoices.clear;
	~harmoniumVoiceOrder.clear;
};

// === PRESET PARTIAL MASKS ===
~harmoniumMasks = (
	allOn: Array.fill(32, 1),
	allOff: [1] ++ Array.fill(31, 0),
	first16: [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
	odds: Array.fill(32, { |i| if((i + 1).odd, 1, 0) }),
	evens: Array.fill(32, { |i| if((i + 1).even, 1, 0) }),
	primes: [0,1,1,0,1,0,1,0,0,0,1,0,1,0,0,0,1,0,1,0,0,0,1,0,0,0,0,0,1,0,1,0],
	octaves: [1,1,0,1,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
	fifths: [1,0,1,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0]
);

// === SOURCE NAMES (updated for vocoder) ===
~harmoniumSources = [
	"Silence", "Sine", "Triangle", "Saw", "Pulse",
	"White Noise", "Pink Noise", "Spectral", "Karplus-Strong", "Harmonic",
	"Gendy1", "Gendy2", "Gendy3", "Lorenz", "Sample",
	"Feedback", "TRACK AUDIO (Vocoder)", "Shepard", "Swarm"
];

// === LPG MODE NAMES ===
~harmoniumLPGModes = [
	"Bypass (VCA only)",
	"LPG Dark",
	"LPG Darker",
	"LPG Normal",
	"LPG Bright",
	"LPG + Distortion"
];

// === FORMATION NAMES ===
~harmoniumFormations = [
	"Harmonic Series",
	"Bark Scale (Psychoacoustic)",
	"Buchla 200 Series"
];

// === MIDI RESPONDERS FOR HARMONIUM ===
// These allow playing Harmonium via MIDI controller (e.g., KeyStep Pro)

~harmoniumMIDIEnabled = false;
~harmoniumMIDINoteOn = nil;
~harmoniumMIDINoteOff = nil;

~harmoniumEnableMIDI = {
	if(~harmoniumMIDIEnabled.not, {
		~harmoniumMIDINoteOn = MIDIFunc.noteOn({ |vel, note, chan|
			~harmoniumNoteOn.(note, vel, chan);
		});
		~harmoniumMIDINoteOff = MIDIFunc.noteOff({ |vel, note, chan|
			~harmoniumNoteOff.(note, chan);
		});
		~harmoniumMIDIEnabled = true;
		"[Harmonium] MIDI input ENABLED - play any MIDI controller".postln;
	});
};

~harmoniumDisableMIDI = {
	if(~harmoniumMIDIEnabled, {
		if(~harmoniumMIDINoteOn.notNil, { ~harmoniumMIDINoteOn.free });
		if(~harmoniumMIDINoteOff.notNil, { ~harmoniumMIDINoteOff.free });
		~harmoniumMIDINoteOn = nil;
		~harmoniumMIDINoteOff = nil;
		~harmoniumMIDIEnabled = false;
		"[Harmonium] MIDI input DISABLED".postln;
	});
};

// === QUICK TEST FUNCTION ===
~harmoniumTest = {
	"[Harmonium] Testing synth output...".postln;
	"[Harmonium] Setting source to SINE (1), bypassing filterbank for clean test".postln;
	~harmoniumParams[\srcSel] = 1;  // Sine
	~harmoniumParams[\bypassBPF] = 1;  // Bypass filterbank for louder/cleaner test
	~harmoniumParams[\amp] = 0.5;
	~harmoniumParams[\wet] = 1.0;
	~harmoniumParams[\lpgMode] = 0;  // No LPG
	~harmoniumNoteOn.(60, 100, 0);
	fork {
		1.5.wait;
		~harmoniumNoteOff.(60, 0);
		0.3.wait;
		~harmoniumParams[\bypassBPF] = 0;  // Re-enable filterbank
		"[Harmonium] Test complete - did you hear a tone?".postln;
		"  If NO sound: Check s.meter; and ensure server is running".postln;
	};
};

"[Harmonium Engine v2.1] 32-band filterbank synth loaded.".postln;
"  - Note on: ~harmoniumNoteOn.(note, vel, chan)".postln;
"  - Note off: ~harmoniumNoteOff.(note, chan)".postln;
"  - Set param: ~harmoniumSetParam.(param, value)".postln;
"  - Panic: ~harmoniumPanic.()".postln;
"  - MIDI: ~harmoniumEnableMIDI.() / ~harmoniumDisableMIDI.()".postln;
"  - Test: ~harmoniumTest.()".postln;
"  - VOCODER MODE (NEW):".postln;
"    • ~enableHarmoniumVocoder.(trackNum, midiNote, velocity)".postln;
"    • ~disableHarmoniumVocoder.()".postln;

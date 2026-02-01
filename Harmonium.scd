(
// HARMONIUM – Trevor Treglia
// trevortreglia.com

s.options.memSize = 1048576;
s.options.numWireBufs = 2048;
s.options.maxNodes = 65536;
s.options.maxSynthDefs = 4096;
s.options.numInputBusChannels = 16;
s.options.sampleRate = 48000;

s.reboot({
    s.waitForBoot({

        var maxPartials = 32;
        var wWidth = 1180, wHeight = 900, ctrlW = 400, btnW = 35, btnH = 20;
        var slH = 140, slW = 16, rowH = 30, labW = 118, nbW = 64, gap = 6;
        var fLbl = Font("Monaco", 11), fVal = Font("Monaco", 10);
        var bgColor = Color.gray(0.15);

        var win, ctrlScroll, ctrlView, gridScroll, gridView, buttons, sliders;
        var srcPM;
        var maskArray, gainArray, nextY = 8;

        var monoSilence, buf, hasBuf = 0, currentSel = 5, kbSample = 0;

        var setMaskAt, setGainAt, setAllMasks, refreshButtons, refreshSliders, loadSample;
        var mkRow, mkLocalRow, mkFreqRow, mkTogglesRow, mkUtilBlock, mkModeDropdown, mkOUBlock;
        var mkFormationBlock, mkSourceBlock, mkSampleBlock, mkModBlock, mkRMFMBlock, mkSMJBlock;
        var mkMaxVoicesMenu, mkADSRGrid, mkEnvLPFBlock, mkInputDeviceBlock, mkDeviceBlock, mkArpBlock, mkFXBlock;
        var mkRecordBlock;
        var meterL, meterR;

        QtGUI.palette = QPalette.dark;

        ~pbRange      = 2;
        ~bend2ratio   = { |bend14| var d = (bend14.clip(0,16383) - 8192) / 8192; 2.pow(d * (~pbRange/12)) };
        ~playMode     = 1;
        ~maxPoly      = 8;
        ~voices       = IdentityDictionary.new;
        ~voiceOrder   = List.new;
        ~chanBend     = Array.fill(16, 8192);
        ~outBus       = 0;
        ~params       = IdentityDictionary.new;
        ~fxParams     = IdentityDictionary.new;
        ~monoHeld     = IdentitySet.new;
        ~monoOrder    = List.new;
        ~busy         = 1;

        ~monoBaseRatio = 1.0;
        ~monoBendRatio = 1.0;

        ~arpOn      = 0;
        ~arpRate    = 4.0;
        ~arpDir     = 0;
        ~arpJitter  = 0.0;
        ~arpMode    = 0;
        ~arpNotes   = List.new;
        ~arpStep    = 0;
        ~arpChan    = 0;
        ~arpClock   = TempoClock.new(1.0);
        ~arpRoutine = nil;
        ~arpLastNote = nil;

        ~polyGroup  = Group.head(s);
        ~synth      = nil;
        ~fxSynth    = nil;

        ~keyStr = { |note, chan, src| (src.asString ++ ":" ++ chan.asString ++ ":" ++ note.asString).asSymbol };
        ~newRandID = { (2147483647.rand).asInteger };
        ~randRange = { |lo, hi| lo + (hi - lo) * 1.0.rand };

        monoSilence = Buffer.alloc(s, 64, 1);
        buf = monoSilence;

        MIDIClient.init; MIDIIn.connectAll;

        ~recordFolder = thisProcess.platform.recordingsDir +/+ "Harmonium";

        ~recording = 0;
        ~meterBus = nil;
        ~meterSynth = nil;
        ~meterRoutine = nil;
        ~recorder = nil;

        ~startRecording = {
            var dirPath, ts, path;

            if(~recording == 1) {
                "Already recording.".postln;
                ^nil;
            };
            if(s.serverRunning.not) {
                "Server not running; can't record.".postln;
                ^nil;
            };

            dirPath = ~recordFolder.asString;

            if(File.exists(dirPath).not) {
                "Creating recording folder: ".post; dirPath.postln;
                File.mkdir(dirPath);
            };

            ts   = Date.localtime.stamp.replace(" ", "_").replace(":", "-");
            path = dirPath +/+ ("harmonium_" ++ ts ++ ".wav");

            ("Recording to: " ++ path).postln;

            s.recHeaderFormat = "wav";
            s.recSampleFormat = "int24";
            s.recChannels     = 2;

            s.prepareForRecord(path);
            s.record;

            ~recording = 1;
        };

        ~stopRecordingSafe = {
            if(~recording == 1) {
                "Stopping recording…".postln;
                s.stopRecording;
                ~recording = 0;
            };
        };

        SynthDef(\harmBankMod, { |out=0,
            gate=0, freeOnDone=0,
            fund=256.60, noteRatio=1, oscFreqMul=1.0, pulseWidth=0.5,
            bufnum=0, playRate=1.0, startPos=0.0, loop=1, trig=0, sampGain=1.0, kbSample=0, sampleRoot=110,
            srcSel=5, hasBuf=0, ouMode=0, num=32, formation=0,
            shepRate=0.0, swarm=0.0,
            rq=0.02, rolloff=1.0, bandRes=0.0, preSat=0.0, makeup=3.0, timbre=0.5,
            useDynamics=1, compThresh=0.25, slopeBelow=0.5, compRatio=6.0,
            clampTime=0.003, relaxTime=0.050,
            useLPF=1, lpfHz=14000, lpf2=0, ceiling=0.98,

            modModeAmp=0, modModePan=0, modModeRM=0, modModeFM=0,
            lfoPatternAmp=0, lfoPatternPan=0, lfoPatternRM=0, lfoPatternFM=0,
            ampDepth=0.0, panDepth=0.0,
            rateMin=0.01, rateMax=0.5, rateSkew=1.0, modComp=1,

            envAtk=0.005, envDec=0.15, envSus=0.7, envRel=0.25,

            envLPFEnable=0, lpfFreq=8000, envLPFRes=0.3,
            lpgMode=0, lpgColor=0.5,

            wet=1.0, amp=1.0,

            subAmp=0.0, subOct1=0, subOct2=0,

            rmEnable=1, rmHz=30, rmDepth=0.0, rmModDepth=0.0, rmTrack=0, rmRatio=1.0, rmRatioNum=1.0, rmRatioDen=1.0,

            fmEnable=1, fmTrack=0, fmHz=100, fmIndex=0.0, fmIndexModDepth=0.0, fmMix=0.0, fmRatioNum=1.0, fmRatioDen=1.0,
            outL=0, outR=1,

            swirlOn=1, swirlRate=0.03, swirlSmooth=2.5, swirlDepth=0.0,

            bootMute=0.0, bootFade=0.02,
            masterMute=0.0,

            smjEnable=0, smjMax=8.0,

            randID=0,

            fbAmt=0.95, fbDelay=0.03, fbDrive=0.2, fbNoise=0.0005, inStereo=0, inChanL=0, inChanR=1, inGain=1.0, inHPFHz=30, inLPFHz=18000,
            fbInject=0.0, noInputFB=0.0, bypassBPF=0, rmSelf=0,

            mask  = #[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
            gains = #[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1], modSlew=0.03 |

            var inputSrc, inSig, maxP, inds, nyq, fundEff, freqsOver, freqsUnder, useUnder, freqs, procSrc;
            var ringOsc, ringSig, rmFreq, rmRatioNumInt, rmRatioDenInt, rmScale;
            var fmFreq, fmRatioNumInt, fmRatioDenInt, fmScaleFM, fmMod, fmCar;
            var swirlWalk;
            var mode, color, cutoff, cutoffMul, pre, dist, fbIn, fbExcite, fbCore, feedbackSrc, qmul, resGain;
            var fbWrite, isSample, indexNoSample, sampleIndex, chosenIndex, srcIndex, src, srcMono;
            var userMask, numMask, valid, actMask, ampWeights, ampWG, rqSafe, bandArea;
            var bankHarm, barkArr, barkFreqs, buchArr, buchFreqs;
            var saw, pulse, sine, tri, white, pink, spec, ks, harmFreqs, keep, harmOsc, gendy1, gendy2, gendy3, lorenz, subSig, shepSrc, swarmSrc, timbreCtl, darkSrc, brightSrc;
            var frames, rateScale, startFrame, sampleMul, sampMono, sampleSrc;
            var envGen, gateEff;
            var ampLFO, ampMod, panLFO, panMod, ampDepthSm, panDepthSm, swirlDepthSm;
            var rateAmp, ratePan, candAmp0, candPan0, wobA, wobP, candAmp1, candPan1, candAmp2, candPan2, candAmp3, candPan3;
            var bands, wetSig, drySig, powerSum, avgAmp, compGain, sig, sigDyn, lpfCut, post, envCut, envLPF, lpgSig;
            var tChange, tOn, tElapsed, smjDelays, smjGates, smjMask;
            var mute, sigOut;
            var rmRate, fmRate, rmLFOCont, rmLFODisc, rmLFOSnH, rmShape, rmDepthEff, rmDepthPre;
            var fmLFOCont, fmLFODisc, fmLFOSnH, fmShape, fmIndexEff;
            var rateMinSafe, rateMaxSafe;
            var killTrig;

            \playMode.kr(0);

            amp        = VarLag.kr(amp.max(0), 0.01);
            wet        = VarLag.kr(wet.clip(0,1), 0.05);
            shepRate   = VarLag.kr(shepRate.clip(-10,10), 0.1);
            swarm      = VarLag.kr(swarm.clip(0,1), 0.1);
            subAmp     = VarLag.kr(subAmp.clip(0,1), 0.02);
            subOct1    = VarLag.kr(subOct1.clip(0,1), 0.02);
            subOct2    = VarLag.kr(subOct2.clip(0,1), 0.02);
            rmDepth    = VarLag.kr(rmDepth, 0.02);
            rmModDepth = VarLag.kr(rmModDepth.clip(0,1), 0.02);
            rmHz       = VarLag.kr(rmHz.max(0.01), 0.02);
            rmEnable   = VarLag.kr(rmEnable.clip(0,1), 0.02);
            bypassBPF  = VarLag.kr(bypassBPF.clip(0,1), 0.02);
            rmSelf     = VarLag.kr(rmSelf.clip(0,1), 0.02);
            fmMix      = VarLag.kr(fmMix, 0.02);
            fmIndex    = VarLag.kr(fmIndex.max(0), 0.02);
            fmIndexModDepth = VarLag.kr(fmIndexModDepth.clip(0,1), 0.02);
            fmEnable   = VarLag.kr(fmEnable.clip(0,1), 0.02);
            envLPFEnable = VarLag.kr(envLPFEnable.clip(0,1), 0.02);
            lpfFreq    = VarLag.kr(lpfFreq.max(20), 0.02);
            bandRes    = VarLag.kr(bandRes, 0.02);
            rq         = VarLag.kr(rq.max(0.0001), 0.02);
            rolloff    = VarLag.kr(rolloff, 0.02);
            fbInject   = VarLag.kr(fbInject.clip(0,1), 0.02);
            noInputFB  = VarLag.kr(noInputFB.clip(0,1), 0.02);

            maxP = 32;
            inds = (1..maxP);
            nyq  = SampleRate.ir * 0.5;

            fundEff = fund.max(0.01) * noteRatio.max(0.001) * oscFreqMul.max(0.001);

            freqsOver  = fundEff * inds;
            freqsUnder = fundEff / inds;
            useUnder   = (ouMode > 0.5);
            bankHarm   = ((1-useUnder)*freqsOver) + (useUnder*freqsUnder);

            barkArr = #[60,150,250,350,450,570,700,840,1000,1170,1370,1600,1850,2150,2500,2900,3400,4000,4800,5800,7000,8500,10500,13500];
            barkFreqs = barkArr ++ Array.fill(maxP - barkArr.size, { 0 });

            buchArr = #[88,125,190,285,430,650,1000,1500,2200,3300,4800,7200,10000,13500,0,0];
            buchFreqs = buchArr ++ Array.fill(maxP - buchArr.size, { 0 });

            freqs = Array.fill(maxP, { |i| Select.kr(formation.clip(0,2), [bankHarm[i], barkFreqs[i], buchFreqs[i]]) });

            userMask = Lag.kr(mask.clip(0,1), modSlew);
            numMask  = (inds <= num);
            valid    = (freqs >= 20) * (freqs <= (nyq*0.9));
            actMask  = Lag.kr(userMask * numMask * valid, modSlew);

            ampWeights = inds.asFloat.pow(rolloff.neg);
            ampWG      = Array.fill(maxP, { |i| ampWeights[i] * gains[i] });

            qmul       = bandRes.clip(0,1).exprange(1, 12);
            rqSafe     = (rq / qmul).max(0.0001);
            bandArea   = rqSafe * qmul;

            inSig = Select.ar(inStereo.clip(0,1), [
                SoundIn.ar(inChanL.clip(0,63)),
                Mix(SoundIn.ar([inChanL.clip(0,63), inChanR.clip(0,63)]))
            ]);
            inSig = HPF.ar(inSig, inHPFHz.clip(10,19000));
            inSig = LPF.ar(inSig, inLPFHz.clip(100,20000));
            inputSrc = inSig * inGain.clip(0,8);

            saw   = VarSaw.ar(fundEff, 0, 0.5);
            pulse = Pulse.ar(fundEff, pulseWidth.clip(0.01,0.99));
            sine  = SinOsc.ar(fundEff);
            tri   = LFTri.ar(fundEff);
            white = WhiteNoise.ar;
            pink  = PinkNoise.ar;

            spec = BPF.ar(WhiteNoise.ar, fundEff * [0.5, 1, 2, 3], 0.1).sum * 0.3;

            ks = Pluck.ar(
                WhiteNoise.ar(0.5),
                Trig1.kr(gate, 0.001),
                1.0 / fundEff.max(20),
                1.0 / fundEff.max(20),
                4.0,
                0.3
            );

            // Harmonic Oscillator: additive sine bank on the harmonic series
            harmFreqs = fundEff * inds;
            keep      = harmFreqs <= nyq;
            harmOsc   = Mix.ar(SinOsc.ar(harmFreqs, 0, keep)) * (1.0 / maxP);

            shepSrc = {
                var num = 10;
                var phase = Phasor.kr(0, shepRate * SampleDur.ir, 0, 1, 0);
                var sig2 = Array.fill(num, { |n|
                    var localPhase = (phase + (n/num)).wrap(0, 1);
                    var freq = fundEff * (2 ** ((localPhase - 0.5) * 4));
                    var amp2  = (((localPhase - 0.5) / 0.2).squared * (-0.5)).exp;
                    SinOsc.ar(freq) * amp2;
                }).sum;
                sig2 * (1.0 / num);
            }.();

            swarmSrc = {
                var num = 8;
                var speed = (shepRate.abs * 6).max(0.1);
                var sig3 = Array.fill(num, { |n|
                    var oct      = n - ((num - 1) * 0.5);
                    var baseFreq = fundEff * (2 ** oct);

                    var rateJitter = 1 + (LFNoise1.kr(0.1 * (n + 1) * speed) * swarm * 4);
                    var rate       = shepRate * rateJitter;

                    var phase  = Phasor.kr(0, rate * SampleDur.ir, 0, 1, 0);
                    var ampEnv = (((phase - 0.5) / 0.25).squared * (-0.5)).exp;

                    var detLFO  = LFNoise1.kr(0.15 * (n + 1) * speed);
                    var detLFOf = LFNoise1.kr(0.07 * (n + 2) * speed);
                    var detAmt  = swarm * 12;
                    var detSemis, detune, freq;
                    detSemis = (detLFO + (detLFOf * 0.5)) * detAmt;
                    detSemis = detSemis.clip2(12);
                    detune  = detSemis.midiratio;

                    freq = baseFreq * detune;
                    SinOsc.ar(freq) * ampEnv;
                }).sum;
                sig3 * (1.0 / num) * 6;
            }.();

            subSig = 0;
            subSig = subSig + (SinOsc.ar(fundEff * 0.5) * subOct1);
            subSig = subSig + (SinOsc.ar(fundEff * 0.25) * subOct2);
            subSig = subSig * subAmp;

            gendy1 = Gendy1.ar;
            gendy2 = Gendy2.ar;
            gendy3 = Gendy3.ar;
            lorenz = LorenzL.ar(freq:50, s:10, r:28, b:2.667);

            fbIn     = LocalIn.ar(1);
            fbExcite = WhiteNoise.ar(fbNoise.clip(0,0.02))
                + Decay2.kr(Trig.kr(gate, 0.005), 0.001, 0.02) * WhiteNoise.ar(fbNoise.clip(0,0.02) * 20);
            fbCore   = DelayC.ar((fbIn * fbAmt.clip(0,0.999)) + fbExcite, 10.0, fbDelay.clip(0.0005,10.0));
            fbCore   = tanh(fbCore * (1 + fbDrive.clip(0,1) * 12));
            feedbackSrc = HPF.ar(fbCore, 30);

            frames    = Select.kr(hasBuf>0.5, [0, BufFrames.kr(bufnum)]);
            rateScale = Select.kr(hasBuf>0.5, [1, BufRateScale.kr(bufnum)]);
            startFrame= startPos.clip(0,1) * frames;
            sampleMul = Select.kr(kbSample>0.5, [1, (fund.max(0.01) * noteRatio.max(0.001)) / sampleRoot.max(1)]);
            sampMono  = Select.ar(hasBuf>0.5, [Silent.ar(1),
                PlayBuf.ar(1, bufnum, playRate*rateScale*sampleMul, trig, startFrame, loop.clip(0,1))
            ]) * sampGain;
            sampleSrc = sampMono;

            isSample      = (srcSel >= 13.5) * (srcSel < 14.5);
            indexNoSample = srcSel.clip(0,18);
            sampleIndex   = Select.kr(hasBuf>0.5, [5,14]);
            chosenIndex   = Select.kr(isSample, [indexNoSample, sampleIndex]);

            srcIndex = VarLag.kr(chosenIndex, 0.02);
            src = SelectX.ar(srcIndex, [
                Silent.ar(1),
                sine,
                tri,
                saw,
                pulse,
                white,
                pink,
                spec,
                ks,
                harmOsc,
                gendy1,
                gendy2,
                gendy3,
                lorenz,
                sampleSrc,
                feedbackSrc,
                inputSrc,
                shepSrc,
                swarmSrc
            ]);

            src = src + (feedbackSrc * fbInject.clip(0,1));
            src = XFade2.ar(src, feedbackSrc, (VarLag.kr(noInputFB.clip(0,1), 0.02) * 2 - 1));

            src     = (src * (1 + preSat.max(0))).tanh;
            srcMono = LeakDC.ar(src);

            timbreCtl = timbre.clip(0,1);
            darkSrc   = LPF.ar(srcMono,  timbreCtl.exprange(800,4000));
            brightSrc = (HPF.ar(srcMono, timbreCtl.exprange(200,4000)) * timbreCtl.linlin(0,1,1,3)).tanh;
            procSrc   = XFade2.ar(darkSrc, brightSrc, timbreCtl.linlin(0,1,-1,1));

            fmRatioNumInt = fmRatioNum.clip(1, 64).round(1);
            fmRatioDenInt = fmRatioDen.clip(1, 64).round(1);
            fmScaleFM = fmRatioNumInt / fmRatioDenInt;

            rmRatioNumInt = rmRatioNum.clip(1, 64).round(1);
            rmRatioDenInt = rmRatioDen.clip(1, 64).round(1);
            rmScale = rmRatioNumInt / rmRatioDenInt;

            rmFreq = ((1 - VarLag.kr(rmTrack.clip(0,1), 0.02)) * rmHz.clip(0.1,20000))
                + (VarLag.kr(rmTrack.clip(0,1), 0.02) * (fundEff * rmScale).clip(0.1,20000));
            ringOsc = SinOsc.ar(rmFreq);
            ringSig = procSrc * ringOsc;

            rateMinSafe = rateMin.max(0.001);
            rateMaxSafe = rateMax.max(rateMinSafe + 0.0001);

            rmRate = Select.kr(
                lfoPatternRM.clip(0,3),
                [
                    Rand(rateMinSafe, rateMaxSafe),
                    LFNoise2.kr(Rand(0.05,0.20)).exprange(rateMinSafe, rateMaxSafe),
                    SinOsc.kr(Rand(0.01,0.10), Rand(0,2pi)).exprange(0.5, 2.0),
                    SinOsc.kr(Rand(0.01,0.10), Rand(0,2pi)).exprange(0.5, 2.0) * 0.1
                ]
            ) * rateSkew.max(0.01);
            rmRate = rmRate.clip(0.001, 40.0);

            fmRate = Select.kr(
                lfoPatternFM.clip(0,3),
                [
                    Rand(rateMinSafe, rateMaxSafe),
                    LFNoise2.kr(Rand(0.05,0.20)).exprange(rateMinSafe, rateMaxSafe),
                    SinOsc.kr(Rand(0.01,0.10), Rand(0,2pi)).exprange(0.5, 2.0),
                    SinOsc.kr(Rand(0.01,0.10), Rand(0,2pi)).exprange(0.5, 2.0) * 0.1
                ]
            ) * rateSkew.max(0.01);
            fmRate = fmRate.clip(0.001, 40.0);

            rmLFOCont = LFNoise2.kr(rmRate);
            rmLFODisc = LFNoise0.kr(rmRate);
            rmLFOSnH  = Latch.kr(LFNoise2.kr(rmRate), Impulse.kr(rmRate.max(0.001)));

            rmShape   = Select.kr(modModeRM.clip(0,2), [rmLFOCont, rmLFODisc, rmLFOSnH]).range(0,1);
            rmDepthEff = (VarLag.kr(rmDepth, 0.02) + (rmShape * rmModDepth)).clip(0,1);
            rmDepthPre  = rmDepthEff * (1 - rmSelf);

            fmLFOCont = LFNoise2.kr(fmRate);
            fmLFODisc = LFNoise0.kr(fmRate);
            fmLFOSnH  = Latch.kr(LFNoise2.kr(fmRate), Impulse.kr(fmRate.max(0.001)));

            fmShape    = Select.kr(modModeFM.clip(0,2), [fmLFOCont, fmLFODisc, fmLFOSnH]).range(0,1);
            fmIndexEff = (VarLag.kr(fmIndex, 0.02) + (fmShape * fmIndexModDepth)).max(0);

            fmFreq = ((1 - VarLag.kr(fmTrack.clip(0,1), 0.02)) * fmHz.clip(0.1,20000))
                + (VarLag.kr(fmTrack.clip(0,1), 0.02) * (fundEff * fmScaleFM).clip(0.1,20000));

            fmMod  = SinOsc.ar(fmFreq);
            fmCar  = FreqShift.ar(procSrc, fmMod * fmIndexEff * fmFreq * fmEnable);

            procSrc = XFade2.ar(procSrc, fmCar, (fmMix * 2 - 1));
            procSrc = XFade2.ar(procSrc, ringSig, (rmDepthPre * 2 - 1));

            gateEff = gate;
            envGen  = EnvGen.kr(Env.adsr(envAtk,envDec,envSus,envRel), gateEff, doneAction:0);

            candAmp0 = Array.fill(maxP, { Rand(rateMinSafe, rateMaxSafe) });
            candPan0 = Array.fill(maxP, { Rand(rateMinSafe, rateMaxSafe) });

            wobA = Array.fill(maxP, {
                SinOsc.kr(Rand(0.01,0.10), Rand(0,2pi)).exprange(0.5, 2.0)
            });
            wobP = Array.fill(maxP, {
                SinOsc.kr(Rand(0.01,0.10), Rand(0,2pi)).exprange(0.5, 2.0)
            });

            candAmp0 = candAmp0 * wobA;
            candPan0 = candPan0 * wobP;

            candAmp1 = Array.fill(maxP, { LFNoise2.kr(Rand(0.05,0.20)).exprange(rateMinSafe, rateMaxSafe) });
            candPan1 = Array.fill(maxP, { LFNoise2.kr(Rand(0.05,0.20)).exprange(rateMinSafe, rateMaxSafe) });

            candAmp2 = (1..maxP).asFloat * 1.0;
            candPan2 = (1..maxP).asFloat * 1.0;
            candAmp3 = (1..maxP).asFloat * 0.1;
            candPan3 = (1..maxP).asFloat * 0.1;

            rateAmp = Array.fill(maxP, { |i|
                (Select.kr(
                    lfoPatternAmp.clip(0,3),
                    [candAmp0[i], candAmp1[i], candAmp2[i], candAmp3[i]]
                ) * rateSkew.max(0.01)).clip(0.001, 40.0);
            });
            ratePan = Array.fill(maxP, { |i|
                (Select.kr(
                    lfoPatternPan.clip(0,3),
                    [candPan0[i], candPan1[i], candPan2[i], candPan3[i]]
                ) * rateSkew.max(0.01)).clip(0.001, 40.0);
            });

            ampLFO = Array.fill(maxP, { |i|
                var rate = rateAmp[i];
                var soft = SinOsc.kr(rate, Rand(0, 2pi));
                var hard = LFPulse.kr(rate, Rand(0, 2pi)).range(-1.0, 1.0);
                var sh   = LFNoise0.kr(rate);
                Select.kr(modModeAmp.clip(0, 2), [soft, hard, sh]).range(0.0, 1.0)
            });

            panLFO = Array.fill(maxP, { |i|
                var rate = ratePan[i];
                var soft = SinOsc.kr(rate, Rand(0, 2pi));
                var hard = LFPulse.kr(rate, Rand(0, 2pi)).range(-1.0, 1.0);
                var sh   = LFNoise0.kr(rate);
                Select.kr(modModePan.clip(0, 2), [soft, hard, sh])
            });

            ampDepthSm   = VarLag.kr(ampDepth.clip(0.0, 1.0), 0.05);
            panDepthSm   = VarLag.kr(panDepth.clip(0.0, 1.0), 0.05);
            ampMod       = (1.0 - ampDepthSm) + (ampDepthSm * ampLFO);
            panMod       = panDepthSm * panLFO;

            swirlWalk = Array.fill(maxP, { |i|
                var phaseOffset = (i / maxP) * 2pi;
                SinOsc.kr(
                    swirlRate.max(0.0001) * LFNoise2.kr(0.1).range(0.5, 1.5),
                    phaseOffset
                )
            });

            swirlDepthSm = VarLag.kr(swirlDepth.clip(0,1), 0.02);
            panMod = panMod + Select.kr(swirlOn.clip(0,1), [0, swirlWalk * swirlDepthSm]);

            resGain = bandRes.clip(0,1).exprange(1, 8);
            bands   = BPF.ar(procSrc * envGen, freqs, rqSafe) * rqSafe * resGain * actMask * ampWG;
            bands   = bands * ampMod;

            tChange   = Changed.kr(gateEff);
            tOn       = tChange * (gateEff > 0);
            tElapsed  = Sweep.kr(tOn, 1.0);
            smjDelays = Array.fill(maxP, { TRand.kr(0, smjMax.max(0), tOn) });
            smjGates  = tElapsed >= smjDelays;
            smjGates  = SetResetFF.kr(smjGates, Done.kr(envGen));
            smjMask   = (1 - smjEnable.clip(0,1)) + (smjEnable.clip(0,1) * smjGates);
            smjMask   = Lag.kr(smjMask, modSlew);
            bands     = bands * smjMask;

            fbWrite = bands.sum;
            fbWrite = LeakDC.ar(fbWrite);
            LocalOut.ar(fbWrite);

            wetSig = Array.fill(maxP, { |i|
                var srcB = bands[i];
                Pan2.ar(srcB, panMod.wrapAt(i));
            }).sum;

            drySig = (procSrc * envGen) ! 2;

            wetSig = Select.ar(bypassBPF.clip(0,1), [wetSig, drySig]);

            envCut = lpfFreq.max(20);
            envLPF = RLPF.ar(XFade2.ar(drySig, wetSig, (wet.clip(0,1)*2-1)), envCut, (1 - envLPFRes.clip(0,0.99)));
            envLPF = XFade2.ar(XFade2.ar(drySig, wetSig, (wet.clip(0,1)*2-1)), envLPF, (VarLag.kr(envLPFEnable.clip(0,1), 0.02)*2-1));

            lpgSig = envLPF;
            mode   = lpgMode.clip(0,5);
            color  = Select.kr(mode, [0.5, 0.0, 0.0, 0.5, 1.0, 0.5]);
            cutoff = envGen.pow(0.6).exprange(80, 12000);
            cutoffMul = Select.kr(mode, [1.0, 1.0, 0.6, 1.0, 1.0, 1.0]);
            cutoff = cutoff * cutoffMul;
            lpgSig = RLPF.ar(lpgSig, cutoff, (1 - (0.2 + (color.clip(0,1)*0.7))));
            lpgSig = lpgSig * envGen.pow(0.7 + (color.clip(0,1)*0.25));
            pre = lpgSig * 3.0;
            dist = pre.tanh * (1/3.0);
            lpgSig = Select.ar(mode, [envLPF, lpgSig, lpgSig, lpgSig, lpgSig, dist]);

            powerSum = (((ampWG * ampWG)*bandArea*actMask).sum) + 1e-9;
            avgAmp   = 1 - (ampDepth.clip(0,1)*0.5);
            compGain = powerSum.reciprocal.sqrt * makeup * Select.kr(modComp.clip(0,1), [1, avgAmp.reciprocal]);

            sig = lpgSig * compGain;

            sigDyn = sig;
            sig = Select.ar(useDynamics>0.5, [sig, sigDyn]);

            lpfCut = lpfHz.clip(20, nyq-10);
            post   = LPF.ar(sig, lpfCut);
            post   = Select.ar(lpf2>0.5, [sig, post]);
            post   = Limiter.ar(LeakDC.ar(post), ceiling.clip(0.1,1.0), 0.005);
            post   = HPF.ar(post, 8);
            post   = post + (WhiteNoise.ar(1e-8) ! 2);

            mute   = Lag.kr(bootMute.clip(0,1), bootFade.max(0.0));
            sigOut = (post + ((subSig * envGen) ! 2)) * envGen * amp * (1 - mute) * (1 - masterMute.clip(0,1));

            killTrig = DetectSilence.ar(sigOut, amp: 0.0001, time: 2.0, doneAction: 0);
            killTrig = Mix(killTrig);
            FreeSelf.kr(killTrig * freeOnDone);

            Out.ar(outL, sigOut[0]);
            Out.ar(outR, sigOut[1]);

            Out.ar(out, sigOut);

            SendTrig.kr(Done.kr(envGen) * freeOnDone, 1, randID);
            FreeSelf.kr(Done.kr(envGen) * freeOnDone);
        }).add;

        SynthDef(\harmDelayVerb, { |inBus=0, outL=0, outR=1,
            delayEnable=0, delaySend=0.0,
            delayTime=0.35, delayFeedback=0.4, delayDamp=3000,
            delayWet=0.0, delayHPF=200, delayLPF=12000,
            verbEnable=0, verbSend=0.0,
            verbWet=0.4, verbRoom=0.7, verbDamp=0.5,
            verbHPF=200, verbLPF=12000|

            var inSig, dry, delIn, del, verbIn, verb, sig;

            inSig = In.ar(inBus, 2);
            dry   = inSig;

            delIn = dry * delaySend.clip(0,1);
            delIn = HPF.ar(LPF.ar(delIn, delayDamp.clip(200,20000)), 20);

            del   = CombL.ar(
                delIn,
                60.0,
                delayTime.clip(0.001, 60.0),
                delayFeedback.linlin(0.0, 1.0, 0.001, 30.0)
            );
            del   = HPF.ar(del, delayHPF.clip(10,10000));
            del   = LPF.ar(del, delayLPF.clip(200,20000));
            del   = del * delayWet.clip(0,1) * delayEnable.clip(0,1);

            verbIn = dry * verbSend.clip(0,1);
            verbIn = HPF.ar(verbIn, verbHPF.clip(10,10000));
            verbIn = LPF.ar(verbIn, verbLPF.clip(200,20000));

            verb = FreeVerb2.ar(
                verbIn[0], verbIn[1],
                verbWet.clip(0,1),
                verbRoom.clip(0,1),
                verbDamp.clip(0,1)
            ) * verbEnable.clip(0,1);

            sig = del + verb;

            OffsetOut.ar(outL, sig[0]);
            OffsetOut.ar(outR, sig[1]);
        }).add;

        SynthDef(\harmMeter, { |bus=0, ctlBus=0|
            var sig = In.ar(bus, 2);
            var lev = Amplitude.kr(sig, 0.01, 0.3);
            Out.kr(ctlBus, lev);
        }).add;

        s.sync;

        ~outBus = Bus.audio(s, 2);

        maskArray = [1!16, 0!16].flatten;
        gainArray = Array.fill(maxPartials,1.0);

        ~params[\amp] = 4.0;
        ~params[\wet] = 1.0;
        ~params[\outL] = 0;
        ~params[\outR] = 1;
        ~params[\srcSel] = 7;

        ~params[\swirlOn] = 1;
        ~params[\swirlRate] = 0.03;
        ~params[\swirlSmooth] = 2.5;

        ~fxParams[\delayEnable]   = 0;
        ~fxParams[\delaySend]     = 0.0;
        ~fxParams[\delayTime]     = 0.35;
        ~fxParams[\delayFeedback] = 0.4;
        ~fxParams[\delayDamp]     = 3000;
        ~fxParams[\delayWet]      = 0.0;
        ~fxParams[\delayHPF]      = 200;
        ~fxParams[\delayLPF]      = 12000;

        ~fxParams[\verbEnable]    = 0;
        ~fxParams[\verbSend]      = 0.0;
        ~fxParams[\verbWet]       = 0.4;
        ~fxParams[\verbRoom]      = 0.7;
        ~fxParams[\verbDamp]      = 0.5;
        ~fxParams[\verbHPF]       = 200;
        ~fxParams[\verbLPF]       = 12000;

        { ~synth.free }.try;
        { ~fxSynth.free }.try;
        { ~meterSynth.free }.try;

        ~polyGroup = Group.head(s);

        ~meterBus = Bus.control(s, 2);

        ~synth = Synth(\harmBankMod, [
            \out, ~outBus, \mask, maskArray, \gains, gainArray,
            \swirlOn, (~params[\swirlOn] ? 0),
            \swirlRate, (~params[\swirlRate] ? 0.01),
            \swirlDepth, (~params[\swirlDepth] ? 0.0),
            \swirlSmooth, (~params[\swirlSmooth] ? 8.0),
            \gate, 0, \freeOnDone, 0,
            \amp, ~params[\amp], \wet, ~params[\wet], \outL, ~params[\outL], \outR, ~params[\outR],
            \bufnum, buf.bufnum, \hasBuf, 0,
            \bootMute, 1.0, \bootFade, 0.02,
            \masterMute, 0.0,
            \randID, ~newRandID.()
        ], target:~polyGroup);

        ~fxSynth = Synth.tail(~polyGroup, \harmDelayVerb,
            [
                \inBus, ~outBus,
                \outL, ~params[\outL],
                \outR, ~params[\outR]
            ] ++ ~fxParams.asPairs
        );

        ~meterSynth = Synth.tail(~polyGroup, \harmMeter, [
            \bus, ~params[\outL],
            \ctlBus, ~meterBus
        ]);

        ~busy = 0;

        ~updateParam = { |key, value|
            ~params[key] = value;
            if(~busy == 1) { ^nil };
            if(~synth.isNil) { ^nil };
            if(key == \mask or: { key == \gains }) {
                ~synth.setn(key, value);
                ~voices.values.do({ |d| if(d[\synth].notNil) { d[\synth].setn(key, value) } });
            }{
                ~synth.set(key, value);
                ~voices.values.do({ |d| if(d[\synth].notNil) { d[\synth].set(key, value) } });
                if(key == \outL or: { key == \outR }) {
                    if(~fxSynth.notNil) { ~fxSynth.set(key, value) };
                };
            };
        };

        ~setFX = { |key, value|
            ~fxParams[key] = value;
            if(~fxSynth.notNil) {
                ~fxSynth.set(key, value);
            };
        };

        ~applyFXDict = { |d|
            d.keysValuesDo { |k, v| ~setFX.(k, v) };
        };

        ~params[\mask] = maskArray;
        ~params[\gains] = gainArray;

        ~allNotesOff = {
            MIDIClient.destinations.do { |d|
                var m = MIDIOut.newByName(d.device, d.name);
                16.do { |ch|
                    m.control(ch, 120, 0);
                    m.control(ch, 123, 0);
                };
                m.free;
            };
        };

        ~rebuildMaster = {
            if(monoSilence.isNil or: { monoSilence.server != s }) {
                monoSilence = Buffer.alloc(s, 64, 1);
            };
            if(buf.isNil) { buf = monoSilence };
            ~busy = 1;
            ~allNotesOff.();
            s.bind {
                ~voices.values.do({ |d| if(d[\synth].notNil) { d[\synth].free } });
                ~voices.clear; ~voiceOrder.clear; ~monoHeld.clear; ~monoOrder.clear;
                if(~synth.notNil) { ~synth.free; ~synth = nil };
                if(~fxSynth.notNil) { ~fxSynth.free; ~fxSynth = nil };
                if(~meterSynth.notNil) { ~meterSynth.free; ~meterSynth = nil };
                if(~polyGroup.notNil) { ~polyGroup.free; ~polyGroup = nil };
                ~polyGroup = Group.head(s);

                ~synth = Synth(\harmBankMod, [
                    \out, ~outBus, \mask, maskArray, \gains, gainArray,
                    \gate, 0, \freeOnDone, 0,
                    \amp, ~params[\amp], \wet, ~params[\wet], \outL, ~params[\outL], \outR, ~params[\outR],
                    \bufnum, buf.bufnum, \hasBuf, hasBuf, \kbSample, kbSample,
                    \bootMute, 1.0, \bootFade, 0.02,
                    \masterMute, 0.0,
                    \randID, ~newRandID.()
                ], target:~polyGroup);

                ~fxSynth = Synth.tail(~polyGroup, \harmDelayVerb,
                    [
                        \inBus, ~outBus,
                        \outL, ~params[\outL],
                        \outR, ~params[\outR]
                    ] ++ ~fxParams.asPairs
                );

                if(~meterBus.isNil) { ~meterBus = Bus.control(s,2) };
                ~meterSynth = Synth.tail(~polyGroup, \harmMeter, [
                    \bus, ~params[\outL],
                    \ctlBus, ~meterBus
                ]);
            };
            ~busy = 0;
        };

        ~panic = { ~rebuildMaster.() };

        ~restartArp = {
            if(~arpRoutine.notNil) {
                ~arpRoutine.stop;
                ~arpRoutine = nil;
            };
            ~arpRoutine = Routine({
                var waitTime, baseRate, jitterAmt;
                var seq, n, note;
                var ratioBase, chanIdx, bendRatio, ratio;
                var dur;
                loop {
                    baseRate  = (~arpRate.max(0.001));
                    jitterAmt = (~arpJitter ? 0.0).clip(0.0, 0.99);
                    waitTime  = baseRate.reciprocal;
                    if(jitterAmt > 0.0) {
                        waitTime = waitTime * (1.0 + (1.0.rand2 * jitterAmt)).max(0.01);
                    };
                    waitTime = waitTime.max(0.02);

                    if(~arpOn == 1 and: { ~synth.notNil }) {

                        if(~arpMode == 0) {
                            if(~arpNotes.notEmpty) {
                                seq = ~arpNotes.asArray.sort;
                                n   = seq.size;
                                if(n > 0) {
                                    switch(~arpDir,
                                        0, {
                                            note = seq[~arpStep % n];
                                        },
                                        1, {
                                            note = seq.reverse[~arpStep % n];
                                        },
                                        2, {
                                            var len = (n * 2) - 2;
                                            var pos = (~arpStep % len);
                                            var up  = (pos < n);
                                            note = up.if({ seq[pos] }, { seq[(len - pos)] });
                                        },
                                        3, {
                                            note = seq.choose;
                                        },
                                        4, {
                                            note = seq.choose + ([-24,-12,0,12,24].choose);
                                        },
                                        5, {
                                            var last = ~arpLastNote ? -1000;
                                            if(seq.size <= 1) {
                                                note = seq[0];
                                            }{
                                                var tries = 0;
                                                note = seq.choose;
                                                while { note == last and: { tries < 8 } } {
                                                    note = seq.choose;
                                                    tries = tries + 1;
                                                };
                                            };
                                        }
                                    );
                                    ~arpLastNote = note;
                                    ~arpStep = ~arpStep + 1;

                                    ratioBase = 2.pow(((note - 60) / 12));
                                    chanIdx   = ~arpChan.clip(0, ~chanBend.size-1);
                                    bendRatio = ~bend2ratio.(~chanBend[chanIdx]);
                                    ratio     = ratioBase * bendRatio;

                                    {
                                        if(~synth.notNil) {
                                            ~synth.set(\noteRatio, ratio);
                                            if(~playMode != 1) {
                                                ~synth.set(\gate, 0);
                                                AppClock.sched(0.01, { ~synth.set(\gate, 1); nil });
                                            };
                                        };
                                    }.defer;

                                    if(~playMode == 1) {
                                        {
                                            var key, v, stealKey, steal;
                                            if(~voices.size >= ~maxPoly) {
                                                stealKey = ~voiceOrder.removeAt(0);
                                                steal = ~voices.removeAt(stealKey);
                                                if(steal.notNil and: { steal[\synth].notNil }) {
                                                    steal[\synth].set(\gate, 0);
                                                };
                                            };
                                            key = ~keyStr.(note, chanIdx, \arp);
                                            v = Synth(\harmBankMod,
                                                ~params.asPairs ++ [
                                                    \out, ~outBus,
                                                    \noteRatio, ratio,
                                                    \gate, 1, \freeOnDone, 1,
                                                    \outL, ~params[\outL], \outR, ~params[\outR],
                                                    \mask, maskArray, \gains, gainArray,
                                                    \bufnum, buf.bufnum, \hasBuf, hasBuf, \kbSample, kbSample,
                                                    \bootMute, 0.0, \bootFade, 0.02,
                                                    \masterMute, 0.0,
                                                    \randID, ~newRandID.()
                                                ],
                                                target: ~polyGroup
                                            );
                                            v.onFree({ { ~voices.removeAt(key); ~voiceOrder.remove(key) }.defer });
                                            ~voices[key] = (synth: v, note: note, chan: chanIdx, src: \arp);
                                            ~voiceOrder.add(key);
                                        }.defer;
                                    };
                                };
                            };
                        }{
                            if(~arpNotes.notEmpty) {
                                seq = ~arpNotes.asArray.sort;
                                note = seq.choose;
                            }{
                                note = 60 + (-12..12).choose;
                            };

                            ratioBase = 2.pow(((note - 60) / 12));
                            chanIdx   = ~arpChan.clip(0, ~chanBend.size-1);
                            bendRatio = ~bend2ratio.(~chanBend[chanIdx]);
                            ratio     = ratioBase * bendRatio;

                            dur = waitTime * ExpRand(0.5, 4.0);

                            {
                                if(~playMode == 1) {
                                    var key, v, stealKey, steal;
                                    if(~voices.size >= ~maxPoly) {
                                        stealKey = ~voiceOrder.removeAt(0);
                                        steal = ~voices.removeAt(stealKey);
                                        if(steal.notNil and: { steal[\synth].notNil }) {
                                            steal[\synth].set(\gate, 0);
                                        };
                                    };
                                    key = ~keyStr.(note, chanIdx, \krell);
                                    v = Synth(\harmBankMod,
                                        ~params.asPairs ++ [
                                            \out, ~outBus,
                                            \noteRatio, ratio,
                                            \gate, 1, \freeOnDone, 1,
                                            \outL, ~params[\outL], \outR, ~params[\outR],
                                            \mask, maskArray, \gains, gainArray,
                                            \bufnum, buf.bufnum, \hasBuf, hasBuf, \kbSample, kbSample,
                                            \bootMute, 0.0, \bootFade, 0.02,
                                            \masterMute, 0.0,
                                            \randID, ~newRandID.()
                                        ],
                                        target: ~polyGroup
                                    );
                                    v.onFree({ { ~voices.removeAt(key); ~voiceOrder.remove(key) }.defer });
                                    ~voices[key] = (synth: v, note: note, chan: chanIdx, src: \krell);
                                    ~voiceOrder.add(key);
                                    AppClock.sched(dur, { v.set(\gate, 0); nil });
                                }{
                                    if(~synth.notNil) {
                                        ~synth.set(\noteRatio, ratio);
                                        ~synth.set(\gate, 0);
                                        AppClock.sched(0.01, { ~synth.set(\gate, 1); nil });
                                        AppClock.sched(dur, { ~synth.set(\gate, 0); nil });
                                    };
                                };
                            }.defer;
                        };
                    };

                    waitTime.wait;
                };
            }).play(~arpClock);
        };
        if(~arpOn == 1) { ~restartArp.() };

        ~releasePoly = { |note, chan, src|
            var key = ~keyStr.(note, chan, src);
            var d = ~voices.removeAt(key);
            if(d.isNil) {
                var fk = ~voices.keys.detect({ |k| var dv = ~voices[k]; dv[\note]==note and: { dv[\chan]==chan } });
                if(fk.notNil) {
                    d = ~voices.removeAt(fk);
                    ~voiceOrder.remove(fk);
                };
            }{
                ~voiceOrder.remove(key);
            };
            if(d.notNil and: { d[\synth].notNil }) { d[\synth].set(\gate, 0) };
        };

        MIDIdef.free(\harmNoteOn); MIDIdef.free(\harmNoteOff); MIDIdef.free(\harmPB);

        MIDIdef.noteOn(\harmNoteOn, { |vel, note, chan, src|
            var key, ratioBase, ratio, v;
            if(s.serverRunning.not) { ^nil };

            ~synth.set(\bootMute, 0.0);

            if(vel == 0) {
                while { ~arpNotes.includes(note) } { ~arpNotes.remove(note) };
            }{
                if(~arpNotes.includes(note).not) {
                    ~arpNotes.add(note);
                    ~arpChan = chan;
                };
            };

            key = ~keyStr.(note, chan, src);

            if(vel == 0) {
                if(~playMode == 0) {
                    ~monoHeld.remove(key); ~monoOrder.remove(key);
                    if(~monoOrder.isEmpty) {
                        ~synth.set(\gate, 0);
                    }{
                        var last = ~monoOrder.last;
                        var parts = last.asString.split($:);
                        var lastNote = parts[2].asInteger;
                        var lastChan = parts[1].asInteger;
                        var ratioBaseL = 2.pow(((lastNote - 60) / 12));
                        var bend = ~chanBend[lastChan];
                        var bendRatioL = ~bend2ratio.(bend);
                        ~monoBaseRatio = ratioBaseL; ~monoBendRatio = bendRatioL;
                        ~synth.set(\noteRatio, ~monoBaseRatio * ~monoBendRatio);
                        ~synth.set(\gate, 0); AppClock.sched(0.02, { ~synth.set(\gate, 1); nil });
                    };
                }{
                    ~releasePoly.(note, chan, src);
                };
                ^nil;
            };

            ratioBase = 2.pow(((note - 60) / 12));
            ratio = ratioBase * ~bend2ratio.(~chanBend[chan]);

            ~synth.set(\bootMute, 0.0);

            if(~playMode == 2) {
                ~synth.set(\masterMute, 0.0, \noteRatio, 1.0, \gate, 0);
                AppClock.sched(0.02, { if(~busy == 0) { ~synth.set(\gate, 1) }; nil });
                ^nil;
            } {
                if(~playMode == 0) {
                    ~synth.set(\masterMute, 0.0);
                    ~monoHeld.add(key);
                    ~monoOrder.remove(key); ~monoOrder.add(key);
                    ~monoBaseRatio = ratioBase;
                    ~monoBendRatio = ~bend2ratio.(~chanBend[chan]);
                    ~synth.set(\noteRatio, ~monoBaseRatio * ~monoBendRatio);
                    ~synth.set(\gate, 0); AppClock.sched(0.02, { ~synth.set(\gate, 1); nil });
                }{
                    if(~playMode == 1) {
                        ~synth.set(\masterMute, 1.0);
                        if(~voices.size >= ~maxPoly) {
                            var stealKey = ~voiceOrder.removeAt(0);
                            var steal = ~voices.removeAt(stealKey);
                            if(steal.notNil) { steal[\synth].set(\gate, 0) };
                        };

                        v = Synth(\harmBankMod,
                            ~params.asPairs ++ [
                                \out, ~outBus,
                                \noteRatio, ratio,
                                \gate, 1, \freeOnDone, 1, \outL, ~params[\outL], \outR, ~params[\outR],
                                \mask, maskArray, \gains, gainArray,
                                \bufnum, buf.bufnum, \hasBuf, hasBuf, \kbSample, kbSample,
                                \bootMute, 0.0, \bootFade, 0.02,
                                \masterMute, 0.0,
                                \randID, ~newRandID.()
                            ],
                            target: ~polyGroup
                        );
                        v.onFree({ { ~voices.removeAt(key); ~voiceOrder.remove(key) }.defer });
                        ~voices[key] = (synth: v, note: note, chan: chan, src: src);
                        ~voiceOrder.add(key);
                    };
                };
            };
        });

        MIDIdef.noteOff(\harmNoteOff, { |vel, note, chan, src|
            var key = ~keyStr.(note, chan, src);
            if(s.serverRunning.not) { ^nil };

            while { ~arpNotes.includes(note) } { ~arpNotes.remove(note) };

            if(~playMode == 2) { ^nil }{
                if(~playMode == 0) {
                    ~monoHeld.remove(key); ~monoOrder.remove(key);
                    if(~monoOrder.isEmpty) {
                        ~synth.set(\gate, 0);
                    }{
                        var last = ~monoOrder.last;
                        var parts = last.asString.split($:);
                        var lastNote = parts[2].asInteger;
                        var lastChan = parts[1].asInteger;
                        var ratioBaseL = 2.pow(((lastNote - 60) / 12));
                        var bend = ~chanBend[lastChan];
                        var bendRatioL = ~bend2ratio.(bend);
                        ~monoBaseRatio = ratioBaseL; ~monoBendRatio = bendRatioL;
                        ~synth.set(\noteRatio, ~monoBaseRatio * ~monoBendRatio);
                        ~synth.set(\gate, 0); AppClock.sched(0.02, { ~synth.set(\gate, 1); nil });
                    };
                }{
                    ~releasePoly.(note, chan, src);
                };
            };
        });

        MIDIdef.bend(\harmPB, { |bend, chan, src|
            if(s.serverRunning.not) { ^nil };
            if(~playMode == 2) { ^nil }{
                if(~playMode == 0) {
                    ~chanBend[chan] = bend;
                    ~monoBendRatio = ~bend2ratio.(bend);
                    ~synth.set(\noteRatio, (~monoBaseRatio * ~monoBendRatio));
                }{
                    var bendRatio;
                    ~chanBend[chan] = bend;
                    bendRatio = ~bend2ratio.(bend);
                    ~voices.do { |d, k|
                        if(d[\chan] == chan and: { d[\src] == src }) {
                            var ratioBase = 2.pow(((d[\note] - 60) / 12));
                            d[\synth].set(\noteRatio, ratioBase * bendRatio);
                        };
                    };
                };
            };
        });

        setMaskAt   = { |i,v| maskArray[i]=v.clip(0,1); ~updateParam.(\mask, maskArray) };
        setGainAt   = { |i,v| gainArray[i]=v.clip(0,1); ~updateParam.(\gains, gainArray) };
        setAllMasks = { |v| maxPartials.do{|i| maskArray[i]=v.clip(0,1)}; };
        refreshButtons = { |bs| maxPartials.do{|i| bs[i].value_(maskArray[i])} };
        refreshSliders = { |ss| maxPartials.do{|i| ss[i].value_(gainArray[i])} };

        loadSample = { |sel|
            var path;
            if(sel.isNil) { ^false };
            path = (sel.class==String).if({ sel }, { sel[0] });
            if(path.isNil) { ^false };
            if(buf.notNil and: { buf !== monoSilence }) { buf.free };
            Buffer.readChannel(s, path, channels:[0], action:{ |b|
                {
                    buf=b; hasBuf=1; currentSel=10;
                    ~updateParam.(\bufnum, buf.bufnum);
                    ~updateParam.(\hasBuf, 1);
                    ~updateParam.(\srcSel, 10);
                }.defer;
            });
            ^true
        };

        mkRow = { |label, min, max, init, step=nil, decimals=0, param|
            var slw, grp, nb, sl, v;
            var isInt, sStep, decs;

            isInt = if(step.notNil, {
                step >= 1
            }, {
                (min.frac == 0) and: {
                    (max.frac == 0) and: {
                        (max - min) <= 128 and: { decimals <= 0 }
                    }
                }
            });

            sStep = if(isInt, { step ? 1 }, { 0.0001 });
            decs  = if(isInt, { 0 }, { [decimals, 4].max });

            slw = (ctrlW-16)-labW-nbW-gap;
            grp = CompositeView(ctrlView, Rect(8,nextY,ctrlW-16,rowH));

            StaticText(grp, Rect(0,4,labW,rowH-10))
                .string_(label)
                .stringColor_(Color.white)
                .font_(fLbl);

            nb = NumberBox(grp, Rect(labW,2,nbW,rowH-6))
                .stringColor_(Color.white)
                .font_(fVal)
                .clipLo_(min)
                .clipHi_(max)
                .decimals_(decs)
                .step_(sStep);

            sl = Slider(grp, Rect(labW+nbW+gap,4,slw,rowH-10));

            sl.action_({
                var vv;
                vv = sl.value.linlin(0,1,min,max);
                if(isInt) {
                    vv = vv.round(sStep);
                }{
                    vv = (vv / sStep).round * sStep;
                };
                vv = vv.clip(min,max);
                nb.value_(vv);
                ~updateParam.(param,vv);
            });

            nb.action_({ |box|
                var vv;
                vv = box.value.clip(min,max);
                if(isInt) {
                    vv = vv.round(sStep);
                    box.value_(vv);
                }{
                    vv = (vv / sStep).round * sStep;
                    box.value_(vv);
                };
                sl.value_(vv.linlin(min,max,0,1).clip(0,1));
                ~updateParam.(param,vv);
            });

            v = init.clip(min,max);
            if(isInt) { v = v.round(sStep) };
            nb.value_(v);
            sl.value_(v.linlin(min,max,0,1).clip(0,1));
            ~updateParam.(param,v);

            nextY = nextY+rowH;
        };

        mkLocalRow = { |label,min,max,init,step=nil,decimals=0,applyFunc|
            var slw, grp, nb, sl, v;
            var isInt, sStep, decs;

            isInt = if(step.notNil, {
                step >= 1
            }, {
                (min.frac == 0) and: {
                    (max.frac == 0) and: {
                        (max - min) <= 128 and: { decimals <= 0 }
                    }
                }
            });

            sStep = if(isInt, { step ? 1 }, { 0.0001 });
            decs  = if(isInt, { 0 }, { [decimals, 4].max });

            slw = (ctrlW-16)-labW-nbW-gap;
            grp = CompositeView(ctrlView, Rect(8,nextY,ctrlW-16,rowH));

            StaticText(grp, Rect(0,4,labW,rowH-10))
                .string_(label)
                .stringColor_(Color.white)
                .font_(fLbl);

            nb = NumberBox(grp, Rect(labW,2,nbW,rowH-6))
                .stringColor_(Color.white)
                .font_(fVal)
                .clipLo_(min)
                .clipHi_(max)
                .decimals_(decs)
                .step_(sStep);

            sl = Slider(grp, Rect(labW+nbW+gap,4,slw,rowH-10));

            sl.action_({
                var vv;
                vv = sl.value.linlin(0,1,min,max);
                if(isInt) {
                    vv = vv.round(sStep);
                }{
                    vv = (vv / sStep).round * sStep;
                };
                vv = vv.clip(min,max);
                nb.value_(vv);
                applyFunc.(vv);
            });

            nb.action_({ |box|
                var vv;
                vv = box.value.clip(min,max);
                if(isInt) {
                    vv = vv.round(sStep);
                    box.value_(vv);
                }{
                    vv = (vv / sStep).round * sStep;
                    box.value_(vv);
                };
                sl.value_(vv.linlin(min,max,0,1).clip(0,1));
                applyFunc.(vv);
            });

            v = init.clip(min,max);
            if(isInt) { v = v.round(sStep) };
            nb.value_(v);
            sl.value_(v.linlin(min,max,0,1).clip(0,1));
            applyFunc.(v);

            nextY = nextY+rowH;
        };

        mkFreqRow = { |label, min, max, init, param|
            var slw, grp, nb, sl, v, decs, fromSlider, toSlider;

            decs = 4;

            fromSlider = { |sv|
                var ratio = max / min;
                (min * (ratio.pow(sv))).clip(min, max)
            };
            toSlider = { |hz|
                var h = hz.clip(min, max);
                ((h / min).log) / ((max / min).log)
            };

            slw = (ctrlW-16)-labW-nbW-gap;
            grp = CompositeView(ctrlView, Rect(8,nextY,ctrlW-16,rowH));

            StaticText(grp, Rect(0,4,labW,rowH-10))
                .string_(label)
                .stringColor_(Color.white)
                .font_(fLbl);

            nb = NumberBox(grp, Rect(labW,2,nbW,rowH-6))
                .stringColor_(Color.white)
                .font_(fVal)
                .clipLo_(min)
                .clipHi_(max)
                .decimals_(decs)
                .step_(0.0001);

            sl = Slider(grp, Rect(labW+nbW+gap,4,slw,rowH-10));

            sl.action_({
                var vv;
                vv = fromSlider.(sl.value);
                vv = (vv / 0.0001).round * 0.0001;
                vv = vv.clip(min, max);
                nb.value_(vv);
                ~updateParam.(param, vv);
            });

            nb.action_({ |box|
                var vv;
                vv = box.value.clip(min, max);
                vv = (vv / 0.0001).round * 0.0001;
                box.value_(vv);
                sl.value_(toSlider.(vv).clip(0,1));
                ~updateParam.(param, vv);
            });

            v = init.clip(min, max);
            v = (v / 0.0001).round * 0.0001;
            nb.value_(v);
            sl.value_(toSlider.(v).clip(0,1));
            ~updateParam.(param, v);

            nextY = nextY + rowH;
        };

        mkTogglesRow = {
            var grp;
            grp = CompositeView(ctrlView, Rect(8,nextY,ctrlW-16,rowH));
            CheckBox(grp,Rect(0,3,110,rowH-8)).string_("Dynamic Processing Enabled").value_(1)
                .action_({|cb| ~updateParam.(\useDynamics,cb.value)}).font_(fVal);
            CheckBox(grp,Rect(120,3,80,rowH-8)).string_("Low-pass Filter Enabled").value_(1)
                .action_({|cb| ~updateParam.(\useLPF,cb.value)}).font_(fVal);
            CheckBox(grp,Rect(206,3,120,rowH-8)).string_("Low-pass Filter 2-Pole").value_(0)
                .action_({|cb| ~updateParam.(\lpf2,cb.value)}).font_(fVal);
            nextY = nextY+rowH;
        };

        mkUtilBlock = {
            var grp;
            grp = CompositeView(ctrlView,Rect(8,nextY,ctrlW-16,rowH)).background_(Color.gray(0.12));
            CheckBox(grp,Rect(0,3,180,rowH-8))
                .string_("MIDI -> Sample").value_(kbSample)
                .action_({|cb| kbSample=cb.value; ~updateParam.(\kbSample,kbSample)}).font_(fVal);

            Button(grp, Rect(190,3,100,rowH-8))
                .states_([["Initialize", Color.white, Color.gray(0.18)]])
                .font_(fVal)
                .action_({
                    ~params = IdentityDictionary.new;
                    ~params[\amp]        = 4.0;
                    ~params[\wet]        = 1.0;
                    ~params[\outL]       = 0;
                    ~params[\outR]       = 1;
                    ~params[\srcSel]     = 7;
                    ~params[\swirlOn]    = 1;
                    ~params[\swirlRate]  = 0.03;
                    ~params[\swirlSmooth]= 2.5;
                    ~params[\swirlDepth] = 0.0;
                    ~params[\bootMute]   = 0.0;
                    ~params[\bootFade]   = 0.02;
                    ~params[\masterMute] = 0.0;

                    ~params[\modModeAmp] = 0; ~params[\modModePan] = 0;
                    ~params[\modModeRM]  = 0; ~params[\modModeFM]  = 0;
                    ~params[\lfoPatternAmp] = 0; ~params[\lfoPatternPan] = 0;
                    ~params[\lfoPatternRM]  = 0; ~params[\lfoPatternFM]  = 0;
                    ~params[\ampDepth]   = 0.0; ~params[\panDepth] = 0.0;
                    ~params[\rateMin]    = 0.01; ~params[\rateMax] = 0.5; ~params[\rateSkew] = 1.0; ~params[\modComp] = 1;

                    ~params[\rmEnable]   = 1; ~params[\rmHz] = 30; ~params[\rmDepth] = 0.0; ~params[\rmModDepth] = 0.0;
                    ~params[\rmTrack]    = 0; ~params[\rmRatio] = 1.0; ~params[\rmRatioNum] = 1.0; ~params[\rmRatioDen] = 1.0;
                    ~params[\fmEnable]   = 1; ~params[\fmTrack] = 0; ~params[\fmHz] = 100;
                    ~params[\fmIndex]    = 0.0; ~params[\fmIndexModDepth] = 0.0; ~params[\fmMix] = 0.0;
                    ~params[\fmRatioNum] = 1.0; ~params[\fmRatioDen] = 1.0;

                    ~params[\rq]         = 0.02; ~params[\rolloff] = 1.0; ~params[\bandRes] = 0.0;
                    ~params[\preSat]     = 0.0; ~params[\makeup] = 3.0; ~params[\timbre] = 0.5;
                    ~params[\useDynamics]= 1; ~params[\compThresh] = 0.25; ~params[\slopeBelow] = 0.5;
                    ~params[\compRatio]  = 6.0; ~params[\clampTime] = 0.003; ~params[\relaxTime] = 0.050;
                    ~params[\useLPF]     = 1; ~params[\lpfHz] = 14000; ~params[\lpf2] = 0;
                    ~params[\ceiling]    = 0.98;

                    ~params[\envAtk]     = 0.005; ~params[\envDec] = 0.15;
                    ~params[\envSus]     = 0.7; ~params[\envRel] = 0.25;
                    ~params[\envLPFEnable] = 0; ~params[\lpfFreq] = 8000; ~params[\envLPFRes] = 0.3;
                    ~params[\lpgMode]    = 0; ~params[\lpgColor] = 0.5;

                    ~params[\subAmp]     = 0.0; ~params[\subOct1] = 0; ~params[\subOct2] = 0;

                    ~params[\shepRate]   = 0.0; ~params[\swarm] = 0.0; ~params[\smjEnable] = 0; ~params[\smjMax] = 8.0;

                    ~params[\fbAmt]      = 0.95; ~params[\fbDelay] = 0.03;
                    ~params[\fbDrive]    = 0.2; ~params[\fbNoise] = 0.0005;
                    ~params[\inStereo]   = 0; ~params[\inChanL] = 0; ~params[\inChanR] = 1;
                    ~params[\inGain]     = 1.0; ~params[\inHPFHz] = 30; ~params[\inLPFHz] = 18000;
                    ~params[\fbInject]   = 0.0; ~params[\noInputFB] = 0.0; ~params[\bypassBPF] = 0; ~params[\rmSelf] = 0;

                    ~params[\fund]       = 256.60; ~params[\noteRatio] = 1.0; ~params[\oscFreqMul] = 1.0; ~params[\pulseWidth] = 0.5;

                    maskArray = [1!16, 0!16].flatten;
                    gainArray = Array.fill(maxPartials, 1.0);
                    ~updateParam.(\mask, maskArray);
                    ~updateParam.(\gains, gainArray);

                    ~params.keysValuesDo({|k,v| ~updateParam.(k,v) });

                    refreshButtons.(buttons);
                    refreshSliders.(sliders);
                    if(srcPM.notNil) { srcPM.value_(~params[\srcSel]); };
                });

            nextY = nextY+rowH;
        };

        mkModeDropdown = {
            var grp, pm;
            grp = CompositeView(ctrlView,Rect(8,nextY,ctrlW-16,rowH));
            StaticText(grp,Rect(0,0,labW,16)).string_("Mode").stringColor_(Color.white).font_(fLbl);
            pm = PopUpMenu(grp,Rect(labW+6,-2,160,20)).background_(Color.gray(0.12)).stringColor_(Color.white)
                .items_(["Monophonic","Polyphonic","Drone"]).value_(~playMode)
                .action_({ |menu|
                    var m = menu.value;
                    if(m == ~playMode) { ^nil };
                    if(~playMode == 2) { ~synth.set(\gate, 0) };
                    ~playMode = m;
                    if(m == 1) {
                        ~synth.set(\masterMute, 1.0);
                        ~synth.set(\gate, 0);
                    }{
                        if(m == 0) {
                            ~synth.set(\masterMute, 0.0);
                            ~synth.set(\gate, 0);
                        }{
                            if(maskArray.sum == 0) { maskArray[0] = 1; ~updateParam.(\mask, maskArray) };
                            ~synth.set(\bootMute, 0.0, \masterMute, 0.0, \freeOnDone, 0, \srcSel, 5);
                            ~voices.values.do({ |d| if(d[\synth].notNil) { d[\synth].free } });
                            ~voices.clear; ~voiceOrder.clear; ~monoHeld.clear; ~monoOrder.clear;
                            ~synth.set(\masterMute, 0.0);
                            ~synth.set(\noteRatio, 1.0);
                            ~synth.set(\gate, 0); AppClock.sched(0.02, { ~synth.set(\gate, 1); nil });
                        };
                    };
                });
            nextY = nextY+rowH;
        };

        mkOUBlock = {
            var grp;
            grp = CompositeView(ctrlView,Rect(8,nextY,ctrlW-16,rowH));
            StaticText(grp,Rect(0,0,labW,16)).string_("Over/Under").stringColor_(Color.white).font_(fLbl);
            PopUpMenu(grp,Rect(labW+6,-2,140,20)).background_(Color.gray(0.12)).stringColor_(Color.white)
                .items_(["Overtones","Undertones"]).value_(0)
                .action_({|pm2| ~updateParam.(\ouMode,pm2.value)});
            nextY = nextY+rowH;
        };

        mkFormationBlock = {
            var grp, pm;
            grp = CompositeView(ctrlView,Rect(8,nextY,ctrlW-16,rowH));
            StaticText(grp,Rect(0,0,labW,16)).string_("Formation").stringColor_(Color.white).font_(fLbl);
            pm = PopUpMenu(grp,Rect(labW+6,-2,140,20)).background_(Color.gray(0.12)).stringColor_(Color.white)
                .items_(["Harmonic","Bark","Buchla 296e"]).value_(0)
                .action_({|pm2| ~updateParam.(\formation, pm2.value)}).font_(fVal);
            { var current = (~params[\formation] ? 0).asInteger.clip(0,2); pm.value_(current) }.try;
            nextY = nextY+rowH;
        };

        mkSourceBlock = {
            var h = rowH+8, grp, srcPMlocal, items;
            grp = CompositeView(ctrlView,Rect(8,nextY,ctrlW-16,h));
            StaticText(grp,Rect(0,0,240,16)).string_("Source").stringColor_(Color.white).font_(fLbl);
            items = ["None","Sine","Triangle","Saw","Pulse","White","Pink","Spectral","Karplus-Strong","Harmonic Oscillator","Gendy1","Gendy2","Gendy3","Lorenz","Sample","No Input Feedback","Input","Shepard","Swarm"];
            srcPMlocal = PopUpMenu(grp,Rect(0,14,260,18)).background_(Color.gray(0.12)).stringColor_(Color.white)
                .items_(items)
                .action_({|pm2|
                    if(pm2.value==15) { ~updateParam.(\noInputFB, 1) }{ ~updateParam.(\noInputFB, 0) };
                    if(pm2.value==14 and: {hasBuf==0}) {
                        Dialog.openPanel({|sel|
                            if(loadSample.(sel)) {
                                currentSel=14; ~updateParam.(\srcSel,14);
                            }{
                                pm2.value_((~params[\srcSel] ? 7).asInteger); ~updateParam.(\srcSel,currentSel);
                            };
                        });
                    }{
                        currentSel=pm2.value; ~updateParam.(\srcSel,currentSel);
                    };
                });
            srcPM = srcPMlocal;
            srcPM.value_((~params[\srcSel] ? 7).asInteger);
            ~updateParam.(\srcSel, currentSel);
            nextY = nextY+h;
        };

        mkSampleBlock = {
            var h = (rowH*4)+12, grp;
            grp = CompositeView(ctrlView,Rect(8,nextY,ctrlW-16,h));
            StaticText(grp,Rect(0,0,260,16)).string_("Sample Controls").stringColor_(Color.white).font_(fLbl);

            Button(grp,Rect(0,18,90,18)).states_([["Load", Color.white, Color.gray(0.18)]])
                .action_({ Dialog.openPanel({|sel| loadSample.(sel) }) });
            Button(grp,Rect(96,18,70,18)).states_([["Free", Color.white, Color.gray(0.18)]])
                .action_({
                    if(buf.notNil and: {buf!==monoSilence}) { buf.free };
                    buf=monoSilence; hasBuf=0;
                    ~updateParam.(\bufnum,buf.bufnum);
                    ~updateParam.(\hasBuf,0);
                    if(currentSel==10) { currentSel=5; ~updateParam.(\srcSel,currentSel) };
                });
            Button(grp,Rect(172,18,70,18)).states_([["Restart", Color.white, Color.gray(0.18)]])
                .action_({
                    ~synth.set(\trig,1);
                    AppClock.sched(0.02,{~synth.set(\trig,0);nil});
                    ~synth.set(\bootMute, 0.0);
                });
            CheckBox(grp,Rect(248,18,80,18)).string_("Loop").value_(1)
                .action_({|cb| ~updateParam.(\loop,cb.value)}).font_(fVal);

            StaticText(grp,Rect(0,44,60,16)).string_("Rate").stringColor_(Color.white).font_(fLbl);
            NumberBox(grp,Rect(64,42,60,18)).stringColor_(Color.white).font_(fVal).clipLo_(-8).clipHi_(8).value_(1)
                .action_({|b| ~updateParam.(\playRate,b.value)});
            StaticText(grp,Rect(130,44,90,16)).string_("Start (0–1)").stringColor_(Color.white).font_(fLbl);
            NumberBox(grp,Rect(224,42,60,18)).stringColor_(Color.white).font_(fVal).clipLo_(0).clipHi_(1).value_(0)
                .action_({|b| ~updateParam.(\startPos,b.value)});

            StaticText(grp,Rect(0,68,110,16)).string_("Sample Freq (Hz)").stringColor_(Color.white).font_(fLbl);
            NumberBox(grp,Rect(114,66,60,18)).stringColor_(Color.white).font_(fVal).clipLo_(20).clipHi_(2000).value_(110)
                .action_({|b| ~updateParam.(\sampleRoot,b.value)});
            StaticText(grp,Rect(0,92,90,16)).string_("Sample Gain").stringColor_(Color.white).font_(fLbl);
            NumberBox(grp,Rect(94,90,60,18)).stringColor_(Color.white).font_(fVal).clipLo_(0).clipHi_(32).value_(1)
                .action_({|b| ~updateParam.(\sampGain,b.value)});

            nextY = nextY+h;
        };

        mkModBlock = {
            var h = (rowH*7)+8, grp;
            grp = CompositeView(ctrlView,Rect(8,nextY,ctrlW-16,h));
            StaticText(grp,Rect(0,0,240,16)).string_("Per-band modulation").stringColor_(Color.white).font_(fLbl);

            StaticText(grp, Rect(0,20,240,16)).string_("Amplitude Modulation Mode").stringColor_(Color.white).font_(fLbl);
            PopUpMenu(grp, Rect(0,36,260,18)).background_(Color.gray(0.12)).stringColor_(Color.white)
                .items_(["Continuous","Discrete","Harmonic (fast)","Harmonic (slow)","LFO (free)","LFO (random)","Sample and Hold"])
                .action_({ |pm2|
                    var v = pm2.value;
                    switch(v,
                        0, { ~updateParam.(\modModeAmp,0); ~updateParam.(\lfoPatternAmp,0) },
                        1, { ~updateParam.(\modModeAmp,1); ~updateParam.(\lfoPatternAmp,0) },
                        2, { ~updateParam.(\modModeAmp,0); ~updateParam.(\lfoPatternAmp,2) },
                        3, { ~updateParam.(\modModeAmp,0); ~updateParam.(\lfoPatternAmp,3) },
                        4, { ~updateParam.(\modModeAmp,0); ~updateParam.(\lfoPatternAmp,0) },
                        5, { ~updateParam.(\modModeAmp,0); ~updateParam.(\lfoPatternAmp,1) },
                        6, { ~updateParam.(\modModeAmp,2); ~updateParam.(\lfoPatternAmp,0) }
                    );
                });

            StaticText(grp, Rect(0,60,240,16)).string_("Pan Mod Mode").stringColor_(Color.white).font_(fLbl);
            PopUpMenu(grp, Rect(0,76,260,18)).background_(Color.gray(0.12)).stringColor_(Color.white)
                .items_(["Continuous","Discrete","Harmonic (fast)","Harmonic (slow)","LFO (free)","LFO (random)","Sample and Hold"])
                .action_({ |pm2|
                    var v = pm2.value;
                    switch(v,
                        0, { ~updateParam.(\modModePan,0); ~updateParam.(\lfoPatternPan,0) },
                        1, { ~updateParam.(\modModePan,1); ~updateParam.(\lfoPatternPan,0) },
                        2, { ~updateParam.(\modModePan,0); ~updateParam.(\lfoPatternPan,2) },
                        3, { ~updateParam.(\modModePan,0); ~updateParam.(\lfoPatternPan,3) },
                        4, { ~updateParam.(\modModePan,0); ~updateParam.(\lfoPatternPan,0) },
                        5, { ~updateParam.(\modModePan,0); ~updateParam.(\lfoPatternPan,1) },
                        6, { ~updateParam.(\modModePan,2); ~updateParam.(\lfoPatternPan,0) }
                    );
                });

            StaticText(grp,Rect(0,100,80,16)).string_("Amp Depth ").stringColor_(Color.white).font_(fLbl);
            NumberBox(grp,Rect(84,98,60,18)).stringColor_(Color.white).font_(fVal).clipLo_(0).clipHi_(1).value_(0)
                .action_({|b| ~updateParam.(\ampDepth,b.value)});
            Slider(grp,Rect(150,100,190,16)).action_({|sl| ~updateParam.(\ampDepth, sl.value.clip(0,1)) });

            StaticText(grp,Rect(0,124,80,16)).string_("Pan depth").stringColor_(Color.white).font_(fLbl);
            NumberBox(grp,Rect(84,122,60,18)).stringColor_(Color.white).font_(fVal).clipLo_(0).clipHi_(1).value_(~params[\panDepth] ? 0.0)
                .action_({|b| ~updateParam.(\panDepth,b.value)});
            Slider(grp,Rect(150,124,190,16)).action_({|sl| ~updateParam.(\panDepth, sl.value.clip(0,1)) });

            StaticText(grp,Rect(0,148,80,16)).string_("Rate min").stringColor_(Color.white).font_(fLbl);
            NumberBox(grp,Rect(84,146,60,18)).stringColor_(Color.white).font_(fVal).clipLo_(0.001).clipHi_(20).value_(0.01)
                .action_({|b| ~updateParam.(\rateMin,b.value)});
            StaticText(grp,Rect(150,148,80,16)).string_("Rate max").stringColor_(Color.white).font_(fLbl);
            NumberBox(grp,Rect(230,146,60,18)).stringColor_(Color.white).font_(fVal).clipLo_(0.002).clipHi_(40).value_(0.5)
                .action_({|b| ~updateParam.(\rateMax,b.value)});

            StaticText(grp,Rect(0,172,80,16)).string_("Rate skew").stringColor_(Color.white).font_(fLbl);
            NumberBox(grp,Rect(84,170,60,18)).stringColor_(Color.white).font_(fVal).clipLo_(0.01).clipHi_(32).value_(1.0)
                .action_({|b| ~updateParam.(\rateSkew,b.value)});
            Slider(grp,Rect(150,172,190,16)).action_({|sl| ~updateParam.(\rateSkew, sl.value.linexp(0,1,0.25,8)) });

            CheckBox(grp,Rect(0,196,220,18)).string_("Mod loudness compensation").value_(1)
                .action_({|cb| ~updateParam.(\modComp,cb.value)}).font_(fVal);
            nextY = nextY+h;
        };

        mkRMFMBlock = {
            var h = (rowH*5)+10, grp;
            grp = CompositeView(ctrlView, Rect(8, nextY, ctrlW-16, h));
            StaticText(grp, Rect(0,0,260,16)).string_("Frequency and Ring Modulation").stringColor_(Color.white).font_(fLbl);

            StaticText(grp, Rect(0,20,240,16)).string_("Ring Modulation Depth Mode").stringColor_(Color.white).font_(fLbl);
            PopUpMenu(grp, Rect(0,36,260,18)).background_(Color.gray(0.12)).stringColor_(Color.white)
                .items_(["Continuous","Discrete","Harmonic (fast)","Harmonic (slow)","LFO (free)","LFO (random)","Sample and Hold"])
                .action_({ |pm2|
                    var v = pm2.value;
                    switch(v,
                        0, { ~updateParam.(\modModeRM,0); ~updateParam.(\lfoPatternRM,0) },
                        1, { ~updateParam.(\modModeRM,1); ~updateParam.(\lfoPatternRM,0) },
                        2, { ~updateParam.(\modModeRM,0); ~updateParam.(\lfoPatternRM,2) },
                        3, { ~updateParam.(\modModeRM,0); ~updateParam.(\lfoPatternRM,3) },
                        4, { ~updateParam.(\modModeRM,0); ~updateParam.(\lfoPatternRM,0) },
                        5, { ~updateParam.(\modModeRM,0); ~updateParam.(\lfoPatternRM,1) },
                        6, { ~updateParam.(\modModeRM,2); ~updateParam.(\lfoPatternRM,0) }
                    );
                });

            StaticText(grp, Rect(0,60,240,16)).string_("FM Index Modulation Mode").stringColor_(Color.white).font_(fLbl);
            PopUpMenu(grp, Rect(0,76,260,18)).background_(Color.gray(0.12)).stringColor_(Color.white)
                .items_(["Continuous","Discrete","Harmonic (fast)","Harmonic (slow)","LFO (free)","LFO (random)","Sample and Hold"])
                .action_({ |pm2|
                    var v = pm2.value;
                    switch(v,
                        0, { ~updateParam.(\modModeFM,0); ~updateParam.(\lfoPatternFM,0) },
                        1, { ~updateParam.(\modModeFM,1); ~updateParam.(\lfoPatternFM,0) },
                        2, { ~updateParam.(\modModeFM,0); ~updateParam.(\lfoPatternFM,2) },
                        3, { ~updateParam.(\modModeFM,0); ~updateParam.(\lfoPatternFM,3) },
                        4, { ~updateParam.(\modModeFM,0); ~updateParam.(\lfoPatternFM,0) },
                        5, { ~updateParam.(\modModeFM,0); ~updateParam.(\lfoPatternFM,1) },
                        6, { ~updateParam.(\modModeFM,2); ~updateParam.(\lfoPatternFM,0) }
                    );
                });

            StaticText(grp,Rect(0,100,120,16)).string_("Ring Mod Depth").stringColor_(Color.white).font_(fLbl);
            NumberBox(grp,Rect(124,98,60,18)).stringColor_(Color.white).font_(fVal).clipLo_(0).clipHi_(1)
                .decimals_(3).step_(0.01).value_(~params[\rmModDepth] ? 0.0)
                .action_({|b| ~updateParam.(\rmModDepth,b.value.clip(0,1))});
            Slider(grp,Rect(190,100,150,16)).action_({|sl| ~updateParam.(\rmModDepth, sl.value.clip(0,1)) });

            StaticText(grp,Rect(0,124,120,16)).string_("FM Mod Depth").stringColor_(Color.white).font_(fLbl);
            NumberBox(grp,Rect(124,122,60,18)).stringColor_(Color.white).font_(fVal).clipLo_(0).clipHi_(1)
                .decimals_(3).step_(0.01).value_(~params[\fmIndexModDepth] ? 0.0)
                .action_({|b| ~updateParam.(\fmIndexModDepth,b.value.clip(0,1))});
            Slider(grp,Rect(190,124,150,16)).action_({|sl| ~updateParam.(\fmIndexModDepth, sl.value.clip(0,1)) });

            nextY = nextY + h;
        };

        mkSMJBlock = {
            var h = (rowH*2)+10, grp;
            grp = CompositeView(ctrlView,Rect(8,nextY,ctrlW-16,h));
            StaticText(grp,Rect(0,0,260,16)).string_("Special Mystic Joy").font_(fLbl).stringColor_(Color.white);
            CheckBox(grp,Rect(0,18,120,18)).string_("Enable").value_(0)
                .action_({|cb| ~updateParam.(\smjEnable, cb.value)}).font_(fVal);
            StaticText(grp,Rect(130,18,140,16)).string_("Maximum Delay (s)").stringColor_(Color.white).font_(fLbl);
            NumberBox(grp,Rect(230,16,60,18)).stringColor_(Color.white).font_(fVal).clipLo_(0).clipHi_(300).value_(8)
                .action_({|b| ~updateParam.(\smjMax, b.value)});
            nextY = nextY+h;
        };

        mkMaxVoicesMenu = {
            var grp, pm, choices, idx, curr;
            choices = [1, 2, 4, 8, 12, 16, 24, 32, 48, 64];
            grp = CompositeView(ctrlView,Rect(8,nextY,ctrlW-16,rowH));
            StaticText(grp,Rect(0,0,labW,16)).string_("Max voices").stringColor_(Color.white).font_(fLbl);
            pm = PopUpMenu(grp,Rect(labW+6,-2,140,20)).background_(Color.gray(0.12)).stringColor_(Color.white)
                .items_(choices.collect(_.asString));
            curr = (~maxPoly ? 16);
            idx = choices.indexOf(curr); if(idx.isNil) { idx = choices.indexOf(16) };
            pm.value_(idx.max(0));
            pm.action_({ |m| ~maxPoly = choices.clipAt(m.value).asInteger; });
            nextY = nextY+rowH;
        };

        mkADSRGrid = {
            var panelW, panelH, panel, bannerMain, nCols, colW, makeCol;

            nCols = 5;
            panelW = gridView.bounds.width - 40;
            panelH = 260;
            colW = (panelW / nCols) - 10;

            panel = CompositeView(gridView, Rect(0, 0, panelW, panelH)).background_(Color.gray(0.12));
            bannerMain = StaticText(panel, Rect(0, 0, panelW, 18))
                .string_("HARMONIUM")
                .font_(Font("Baskerville", 20).boldVariant)
                .align_(\center)
                .stringColor_(Color.white);

            makeCol = { |label, min, max, init, step, decimals, param, colIndex|
                var col, sl, nb, sw=28, h=150, x, setBoth;
                x = (colIndex * (panelW / nCols)) + 10;
                col = CompositeView(panel, Rect(x, 24, colW, panelH - 30)).background_(Color.gray(0.12));
                StaticText(col, Rect(0, 0, colW, 16)).string_(label).font_(fLbl).stringColor_(Color.white);
                sl = Slider(col, Rect((colW - sw) * 0.5, 18, sw, h)).orientation_(\vertical);
                nb = NumberBox(col, Rect((colW - 60) * 0.5, 192, 60, 20)).stringColor_(Color.white).font_(fVal)
                    .clipLo_(min).clipHi_(max).decimals_(decimals).step_(step);

                setBoth = { |v|
                    v = v.clip(min, max);
                    nb.value_(v);
                    sl.value_(v.linlin(min, max, 0, 1).clip(0,1));
                    ~updateParam.(param, v);
                };

                sl.action_({ |s|
                    var v = s.value.linlin(0, 1, min, max);
                    if(step.notNil) { v = (v / step).round * step };
                    setBoth.(v);
                });
                nb.action_({ |b|
                    var v = b.value.clip(min, max);
                    if(step.notNil) { v = (v / step).round * step; b.value_(v) };
                    setBoth.(v);
                });

                setBoth.((~params[param] ? init));
            };

            makeCol.("Attack",  0.001, 60, ~params[\envAtk] ? 0.005, 0.0001, 4, \envAtk, 0);
            makeCol.("Decay",   0.001, 60, ~params[\envDec] ? 0.15,  0.0001, 4, \envDec, 1);
            makeCol.("Sustain", 0,     1, ~params[\envSus] ? 0.7,   0.0001, 4, \envSus, 2);
            makeCol.("Release", 0.01, 120, ~params[\envRel] ? 0.25, 0.0001, 4, \envRel, 3);

            {
                var x, col, choices, popup, initMode;
                x = (4 * (panelW / nCols)) + 10;
                col = CompositeView(panel, Rect(x, 24, colW, panelH - 30)).background_(Color.gray(0.12));
                StaticText(col, Rect(0, 0, colW, 16)).string_("Low Pass Gate").font_(fLbl).stringColor_(Color.white);
                choices = ["Off", "Dark", "Darker", "Neutral", "Bright", "Distorted"];
                popup = PopUpMenu(col, Rect((colW - 140) * 0.5, 22, 140, 20)).items_(choices).background_(Color.gray(0.12)).stringColor_(Color.white);
                initMode = (~params[\lpgMode] ? 0).asInteger.clip(0,5);
                popup.value_(initMode);
                ~updateParam.(\lpgMode, initMode);
                ~updateParam.(\lpgColor, [0.5, 0.0, 0.0, 0.5, 1.0, 0.5].clipAt(initMode));
                popup.action_({ |p|
                    var idx = p.value.clip(0, choices.size - 1);
                    ~updateParam.(\lpgMode, idx);
                    ~updateParam.(\lpgColor, [0.5, 0.0, 0.0, 0.5, 1.0, 0.5].clipAt(idx));
                });
            }.();
        };

        mkEnvLPFBlock = { };

        mkArpBlock = {
            var panelW, panelH, grp, rateMin, rateMax, rateNB, rateSL, dirPM, jitterSL, modePM;
            rateMin = 0.01;
            rateMax = 16.0;
            panelW = gridView.bounds.width - 40;
            panelH = 110;

            grp = CompositeView(gridView, Rect(0, 0, panelW, panelH)).background_(Color.gray(0.12));

            StaticText(grp, Rect(0, 0, panelW, 18))
                .string_("Arpeggiator")
                .font_(fLbl)
                .align_(\center)
                .stringColor_(Color.white);

            CheckBox(grp, Rect(10, 26, 80, 18))
                .string_("Enable")
                .value_(~arpOn)
                .action_({ |cb|
                    ~arpOn = cb.value.asInteger;
                    if(~arpOn == 1) {
                        if(~arpRoutine.notNil) {
                            ~arpRoutine.stop;
                            ~arpRoutine = nil;
                        };
                        ~restartArp.();
                    }{
                        if(~arpRoutine.notNil) {
                            ~arpRoutine.stop;
                            ~arpRoutine = nil;
                        };
                    };
                })
                .font_(fVal);

            StaticText(grp, Rect(100, 28, 60, 16))
                .string_("Rate (Hz)")
                .stringColor_(Color.white)
                .font_(fLbl);

            rateNB = NumberBox(grp, Rect(160, 26, 60, 18))
                .stringColor_(Color.white)
                .font_(fVal)
                .clipLo_(rateMin)
                .clipHi_(rateMax)
                .value_(~arpRate)
                .action_({ |nb|
                    var v = nb.value.clip(rateMin, rateMax);
                    ~arpRate = v;
                    rateSL.value_(v.explin(rateMin, rateMax, 0, 1).clip(0,1));
                });

            rateSL = Slider(grp, Rect(228, 26, panelW - 238, 18))
                .action_({ |sl|
                    var v = sl.value.linexp(0, 1, rateMin, rateMax);
                    ~arpRate = v;
                    rateNB.value_(v);
                });
            rateSL.value_(~arpRate.explin(rateMin, rateMax, 0, 1).clip(0,1));

            StaticText(grp, Rect(10, 52, 80, 16))
                .string_("Direction")
                .stringColor_(Color.white)
                .font_(fLbl);

            dirPM = PopUpMenu(grp, Rect(90, 50, 200, 20))
                .items_(["Up","Down","Up-Down","Random","Rand+Oct","Rand Other"])
                .background_(Color.gray(0.12))
                .stringColor_(Color.white)
                .value_(~arpDir.clip(0,5))
                .action_({ |pm|
                    ~arpDir = pm.value.asInteger.clip(0,5);
                })
                .font_(fVal);

            StaticText(grp, Rect(310, 52, 60, 16))
                .string_("Mode")
                .stringColor_(Color.white)
                .font_(fLbl);

            modePM = PopUpMenu(grp, Rect(370, 50, 140, 20))
                .items_(["Arp","Krell"])
                .background_(Color.gray(0.12))
                .stringColor_(Color.white)
                .value_(~arpMode.clip(0,1))
                .action_({ |pm|
                    ~arpMode = pm.value.asInteger.clip(0,1);
                    if(~arpOn == 1) { ~restartArp.() };
                })
                .font_(fVal);

            StaticText(grp, Rect(10, 80, 60, 16))
                .string_("Jitter")
                .stringColor_(Color.white)
                .font_(fLbl);

            jitterSL = Slider(grp, Rect(70, 80, panelW - 80, 18))
                .action_({ |sl|
                    ~arpJitter = sl.value.clip(0, 1);
                });
            jitterSL.value_((~arpJitter ? 0.0).clip(0, 1));
        };

        mkFXBlock = {
            var panelW, panelH, grp;

            var delayEnableCB, delaySendSL, delayWetSL;
            var dTimeNB, dTimeSL, fbNB, fbSL;

            var verbEnableCB, verbSendSL, verbWetSL;
            var roomNB, dampNB;

            panelW = gridView.bounds.width - 40;
            panelH = 160;

            grp = CompositeView(gridView, Rect(0, 0, panelW, panelH)).background_(Color.gray(0.12));

            StaticText(grp, Rect(0, 0, panelW, 18))
                .string_("FX")
                .font_(fLbl)
                .align_(\center)
                .stringColor_(Color.white);

            delayEnableCB = CheckBox(grp, Rect(10, 26, 80, 18))
                .string_("Delay")
                .value_(~fxParams[\delayEnable] ? 0)
                .action_({ |cb| ~setFX.(\delayEnable, cb.value.asInteger) })
                .font_(fVal);

            StaticText(grp, Rect(100, 28, 40, 16))
                .string_("Send")
                .stringColor_(Color.white)
                .font_(fLbl);

            delaySendSL = Slider(grp, Rect(140, 26, 120, 18))
                .action_({ |sl| ~setFX.(\delaySend, sl.value.clip(0,1)) });
            delaySendSL.value_((~fxParams[\delaySend] ? 0.0).clip(0,1));

            StaticText(grp, Rect(270, 28, 40, 16))
                .string_("Wet")
                .stringColor_(Color.white)
                .font_(fLbl);

            delayWetSL = Slider(grp, Rect(310, 26, panelW - 320, 18))
                .action_({ |sl| ~setFX.(\delayWet, sl.value.clip(0,1)) });
            delayWetSL.value_((~fxParams[\delayWet] ? 0.0).clip(0,1));

            StaticText(grp, Rect(10, 56, 70, 16))
                .string_("Delay (s)")
                .stringColor_(Color.white)
                .font_(fLbl);

            dTimeNB = NumberBox(grp, Rect(80, 54, 60, 18))
                .stringColor_(Color.white)
                .font_(fVal)
                .clipLo_(0.01)
                .clipHi_(60.0)
                .value_(~fxParams[\delayTime] ? 0.35)
                .action_({ |nb|
                    var v = nb.value.clip(0.01, 60.0);
                    ~setFX.(\delayTime, v);
                    dTimeSL.value_(v.linlin(0.01, 60.0, 0, 1).clip(0,1));
                });

            dTimeSL = Slider(grp, Rect(146, 54, 120, 18))
                .action_({ |sl|
                    var v = sl.value.linlin(0,1,0.01,60.0);
                    ~setFX.(\delayTime, v);
                    dTimeNB.value_(v);
                });
            dTimeSL.value_((~fxParams[\delayTime] ? 0.35).linlin(0.01,60.0,0,1).clip(0,1));

            StaticText(grp, Rect(270, 56, 70, 16))
                .string_("Feedback")
                .stringColor_(Color.white)
                .font_(fLbl);

            fbNB = NumberBox(grp, Rect(340, 54, 60, 18))
                .stringColor_(Color.white)
                .font_(fVal)
                .clipLo_(0.0)
                .clipHi_(0.99)
                .value_(~fxParams[\delayFeedback] ? 0.4)
                .action_({ |nb|
                    var v = nb.value.clip(0.0, 0.99);
                    ~setFX.(\delayFeedback, v);
                    fbSL.value_(v.clip(0,1));
                });

            fbSL = Slider(grp, Rect(406, 54, panelW - 416, 18))
                .action_({ |sl|
                    var v = sl.value.clip(0,0.99);
                    ~setFX.(\delayFeedback, v);
                    fbNB.value_(v);
                });
            fbSL.value_((~fxParams[\delayFeedback] ? 0.4).clip(0,0.99));

            verbEnableCB = CheckBox(grp, Rect(10, 86, 80, 18))
                .string_("Reverb")
                .value_(~fxParams[\verbEnable] ? 0)
                .action_({ |cb| ~setFX.(\verbEnable, cb.value.asInteger) })
                .font_(fVal);

            StaticText(grp, Rect(100, 88, 40, 16))
                .string_("Send")
                .stringColor_(Color.white)
                .font_(fLbl);

            verbSendSL = Slider(grp, Rect(140, 86, 120, 18))
                .action_({ |sl| ~setFX.(\verbSend, sl.value.clip(0,1)) });
            verbSendSL.value_((~fxParams[\verbSend] ? 0.0).clip(0,1));

            StaticText(grp, Rect(270, 88, 40, 16))
                .string_("Wet")
                .stringColor_(Color.white)
                .font_(fLbl);

            verbWetSL = Slider(grp, Rect(310, 86, panelW - 320, 18))
                .action_({ |sl| ~setFX.(\verbWet, sl.value.clip(0,1)) });
            verbWetSL.value_((~fxParams[\verbWet] ? 0.4).clip(0,1));

            StaticText(grp, Rect(10, 116, 60, 16))
                .string_("Room")
                .stringColor_(Color.white)
                .font_(fLbl);

            roomNB = NumberBox(grp, Rect(70, 114, 60, 18))
                .stringColor_(Color.white)
                .font_(fVal)
                .clipLo_(0.0)
                .clipHi_(1.0)
                .value_(~fxParams[\verbRoom] ? 0.7)
                .action_({ |nb|
                    var v = nb.value.clip(0.0,1.0);
                    ~setFX.(\verbRoom, v);
                });

            StaticText(grp, Rect(140, 116, 60, 16))
                .string_("Damp")
                .stringColor_(Color.white)
                .font_(fLbl);

            dampNB = NumberBox(grp, Rect(200, 114, 60, 18))
                .stringColor_(Color.white)
                .font_(fVal)
                .clipLo_(0.0)
                .clipHi_(1.0)
                .value_(~fxParams[\verbDamp] ? 0.5)
                .action_({ |nb|
                    var v = nb.value.clip(0.0,1.0);
                    ~setFX.(\verbDamp, v);
                });
        };

        mkRecordBlock = {
            var h = rowH + 40, grp, btn;

            grp = CompositeView(ctrlView, Rect(8, nextY, ctrlW-16, h)).background_(Color.gray(0.12));
            StaticText(grp, Rect(0,0,labW,16)).string_("Recording").stringColor_(Color.white).font_(fLbl);

            btn = Button(grp, Rect(0,18,140,rowH-6))
                .states_([
                    ["● Record", Color.red, Color.gray(0.18)],
                    ["■ Stop",   Color.white, Color.red]
                ])
                .font_(fVal)
                .action_({ |b|
                    if(b.value == 1) {
                        ~startRecording.();
                        if(~recording == 0) {
                            b.value_(0);
                        };
                    }{
                        ~stopRecordingSafe.();
                    };
                });

            meterL = LevelIndicator(grp, Rect(150, 18, (ctrlW-16-160)/2, rowH-6))
                .warning_(0.7)
                .critical_(0.9)
                .value_(0);
            meterR = LevelIndicator(grp, Rect(150 + (ctrlW-16-160)/2 + 4, 18, (ctrlW-16-160)/2, rowH-6))
                .warning_(0.7)
                .critical_(0.9)
                .value_(0);

            if(~meterRoutine.isNil) {
                ~meterRoutine = Routine({
                    loop {
                        if(
                            ~meterBus.notNil
                            and: { ~meterBus.server.notNil }
                            and: { ~meterBus.server.serverRunning }
                        ) {
                            ~meterBus.getn(2, { |v|
                                {
                                    if(meterL.notNil) { meterL.value_(v[0].clip(0,1)); };
                                    if(meterR.notNil) { meterR.value_(v[1].clip(0,1)); };
                                }.defer;
                            });
                        };
                        0.05.wait;
                    }
                }).play(AppClock);
            };

            nextY = nextY + h + 4;
        };

        mkInputDeviceBlock = {
            var h, grp, inDD, refresh;
            h = rowH + 32;
            grp = CompositeView(ctrlView, Rect(8, nextY, ctrlW-16, h));
            StaticText(grp, Rect(0,0,labW,16)).string_("Input device").stringColor_(Color.white).font_(fLbl);
            inDD = PopUpMenu(grp, Rect(labW+6,-2, ctrlW - (labW+14), 20)).background_(Color.gray(0.12)).stringColor_(Color.white);
            inDD.action_({ |pm2|
                var names, sel, name;
                names = ServerOptions.inDevices ?? { [] };
                sel   = pm2.value;
                if(names.isEmpty.not and: { sel < names.size }) {
                    name = names[sel];
                    if(name != s.options.inDevice) {
                        s.options.inDevice = name;
                        if(name.asString.find("16").notNil) {
                            s.options.numInputBusChannels = 16;
                        }{
                            s.options.numInputBusChannels = 2;
                        };
                        s.reboot({
                            s.waitForBoot({
                                monoSilence = Buffer.alloc(s, 64, 1);
                                buf = monoSilence;
                                { ~rebuildMaster.() }.try;
                            });
                        });
                    };
                };
            });
            refresh = {
                var ins = ServerOptions.inDevices ?? { [] };
                var idx = ins.indexOf(s.options.inDevice);
                if(ins.isEmpty.not) { inDD.items_(ins) } { inDD.items_(["(no inputs)"]) };
                if(idx.isNil) { idx = 0 };
                inDD.value_(idx);
            };
            refresh.value;
            nextY = nextY + h + 8;
        };

        mkDeviceBlock = {
            var h, grp, outDD, refresh;
            h = rowH + 32;
            grp = CompositeView(ctrlView, Rect(8, nextY, ctrlW-16, h));
            StaticText(grp, Rect(0,0,labW,16)).string_("Output device").stringColor_(Color.white).font_(fLbl);

            outDD = PopUpMenu(grp, Rect(labW+6,-2, ctrlW - (labW+14), 20)).background_(Color.gray(0.12)).stringColor_(Color.white);

            outDD.action_({ |pm2|
                var names, sel, inNames;
                names   = ServerOptions.outDevices ?? { [] };
                sel     = pm2.value;
                inNames = ServerOptions.inDevices ?? { [] };
                if(sel.notNil and: { sel < names.size }) {
                    var name = names[sel];
                    if(s.options.outDevice != name) {
                        s.options.outDevice_(name);
                        if(inNames.notNil and: { inNames.indexOf(name).notNil }) {
                            s.options.inDevice_(name);
                        };
                        s.reboot;
                        AppClock.sched(0.8, { ~rebuildMaster.(); nil });
                    };
                };
            });

            refresh = {
                var outs = ServerOptions.outDevices ?? { [] };
                var idx  = outs.indexOf(s.options.outDevice);
                if(outs.isEmpty.not) {
                    outDD.items_(outs);
                }{
                    outDD.items_( ["(no outputs)"] );
                };
                if(idx.isNil) { idx = 0 };
                outDD.value_(idx);
            };

            refresh.value;
            nextY = nextY + h + 8;
        };

        win = Window("",Rect(80,60,wWidth,wHeight)).front;
        win.view.background_(bgColor);

        win.view.keyDownAction_({ |view, char, modifiers, unicode, keycode|
            if(unicode == 27) { ~panic.() };
        });

        ctrlScroll = ScrollView(win,Rect(8,8,ctrlW,wHeight-16))
            .hasVerticalScroller_(true)
            .hasHorizontalScroller_(false)
            .background_(Color.gray(0.12));
        ctrlView = CompositeView(ctrlScroll,Rect(0,0,ctrlW-16,2800))
            .background_(Color.gray(0.12));

        gridScroll = ScrollView(win,Rect(ctrlW+16,8,wWidth-ctrlW-24,wHeight-16))
            .hasVerticalScroller_(true)
            .hasHorizontalScroller_(false)
            .background_(Color.gray(0.12));
        gridView = CompositeView(gridScroll,Rect(0,0,wWidth-ctrlW-40,2000))
            .background_(Color.gray(0.12));
        gridView.decorator = FlowLayout(gridView.bounds,10@8,8@6);

        mkTogglesRow.();
        mkUtilBlock.();
        mkModeDropdown.();
        mkMaxVoicesMenu.();
        mkOUBlock.();
        mkFormationBlock.();
        mkSourceBlock.();
        mkSampleBlock.();
        mkModBlock.();
        mkRMFMBlock.();

        {
            var grp;
            grp = CompositeView(ctrlView, Rect(8, nextY, ctrlW-16, rowH));
            CheckBox(grp, Rect(0,3,100,rowH-8)).string_("Swirl Enabled").value_(~params[\swirlOn] ? 0)
                .action_({ |cb| ~updateParam.(\swirlOn, cb.value) }).font_(fVal);
            nextY = nextY + rowH;
        }.();

        mkRow.( "Swirl rate (Hz)", 0.0005, 1.0, (~params[\swirlRate] ? 0.01), nil, 4, \swirlRate);
        mkRow.( "Swirl smooth (s)",0.01,  60.0, (~params[\swirlSmooth] ? 8.0), nil, 2, \swirlSmooth);

        {
            var grp;
            grp = CompositeView(ctrlView, Rect(8, nextY, ctrlW-16, rowH));
            CheckBox(grp, Rect(0,3,160,rowH-8)).string_("FM Tracking").value_(0)
                .action_({ |cb| ~updateParam.(\fmTrack, cb.value) }).font_(fVal);
            nextY = nextY + rowH;
        }.();

        mkFreqRow.( "FM Hz", 0.1, 20000, (~params[\fmHz] ? 100.0), \fmHz);
        mkRow.( "FM index",    0.0, 10.0,  0.0,   nil, 3, \fmIndex);
        mkRow.( "FM mix",      0.0, 1.0,   0.0,   nil, 3, \fmMix);
        mkRow.( "FM ratio num",1,   64,    1,     1,     0, \fmRatioNum);
        mkRow.( "FM ratio den",1,   64,    1,     1,     0, \fmRatioDen);

        mkSMJBlock.();

        mkFreqRow.( "Ring Hz", 0.1, 20000, (~params[\rmHz] ? 30.0), \rmHz);
        mkRow.( "Ring depth", 0.0, 1.0, 0.0, nil, 3, \rmDepth);

        {
            var grp;
            grp = CompositeView(ctrlView, Rect(8, nextY, ctrlW-16, rowH));
            CheckBox(grp, Rect(0,3,160,rowH-8)).string_("RM Tracking").value_(0)
                .action_({ |cb| ~updateParam.(\rmTrack, cb.value) }).font_(fVal);
            nextY = nextY + rowH;
        }.();

        {
            var grp;
            grp = CompositeView(ctrlView, Rect(8, nextY, ctrlW-16, rowH));
            CheckBox(grp, Rect(0,3,160,rowH-8)).string_("RM self (post)").value_(~params[\rmSelf] ? 0)
                .action_({ |cb| ~updateParam.(\rmSelf, cb.value) }).font_(fVal);
            nextY = nextY + rowH;
        }.();

        mkRow.( "Ring ratio num", 1, 64, 1, 1, 0, \rmRatioNum);
        mkRow.( "Ring ratio den", 1, 64, 1, 1, 0, \rmRatioDen);

        mkFreqRow.( "Fund Hz", 20, 2000, (~params[\fund] ? 261.620), \fund);

        mkRow.( "Num partials",   1,maxPartials,32,1,0,\num);
        mkRow.( "RQ (bandwidth)", 0.0001,0.2,0.02,0.0001,6,\rq);
        mkRow.( "Rolloff exp",    0,3,1,0.001,3,\rolloff);
        mkRow.( "Band Resonance", 0,1,0,0.001,3,\bandRes);
        mkRow.( "Shepard rate",  -3,3,0,0.01,3,\shepRate);
        mkRow.( "Swarm",          0,1,0,0.01,3,\swarm);

        {
            var grp;
            grp = CompositeView(ctrlView, Rect(8, nextY, ctrlW-16, rowH));
            CheckBox(grp, Rect(0,3,200,rowH-8)).string_("Bypass bandpass filterbank").value_(~params[\bypassBPF] ? 0)
                .action_({ |cb| ~updateParam.(\bypassBPF, cb.value) }).font_(fVal);
            nextY = nextY + rowH;
        }.();

        mkRow.( "Pre-sat drive",  0,6,0,0.001,3,\preSat);
        mkRow.( "Makeup gain",    0.2,40,3,0.001,3,\makeup);
        mkRow.( "Timbre",         0,1,0.5,0.001,3,\timbre);
        mkRow.( "Comp threshold", 0.01,1.5,0.25,0.001,3,\compThresh);
        mkRow.( "Gate slope",     0.05,1,0.5,0.001,3,\slopeBelow);
        mkRow.( "Comp ratio",     1,20,6,0.001,3,\compRatio);
        mkRow.( "LPF cut Hz",     20,20000,14000,1,0,\lpfHz);
        mkRow.( "Limiter ceil",   0.1,1,0.98,0.001,3,\ceiling);
        mkRow.( "Wet",            0,1,1,0.001,3,\wet);
        mkRow.( "Amp",            0,200,4,0.001,3,\amp);

        mkRow.( "Sub Amp",        0,1,0,0.001,3,\subAmp);

        {
            var grp;
            grp = CompositeView(ctrlView, Rect(8, nextY, ctrlW-16, rowH));
            CheckBox(grp, Rect(0,3,180,rowH-8)).string_("Sub -1 octave").value_(~params[\subOct1] ? 0)
                .action_({ |cb| ~updateParam.(\subOct1, cb.value) }).font_(fVal);
            CheckBox(grp, Rect(190,3,180,rowH-8)).string_("Sub -2 octaves").value_(~params[\subOct2] ? 0)
                .action_({ |cb| ~updateParam.(\subOct2, cb.value) }).font_(fVal);
            nextY = nextY + rowH;
        }.();

        mkRow.( "Input gain",    0,8,1,0.001,3,\inGain);
        mkRow.( "Input HPF Hz",  10,1000,30,1,0,\inHPFHz);
        mkRow.( "Input LPF Hz",  500,20000,18000,1,0,\inLPFHz);

        {
            var grp, pm, nbL, nbR;
            grp = CompositeView(ctrlView, Rect(8, nextY, ctrlW-16, rowH));
            StaticText(grp, Rect(0, 0, labW, 16)).string_("Input mode").stringColor_(Color.white).font_(fLbl);
            pm = PopUpMenu(grp, Rect(labW+6, -2, 120, 20)).background_(Color.gray(0.12)).stringColor_(Color.white)
                .items_(["Mono","Stereo"]).value_((~params[\inStereo] ? 0).asInteger)
                .action_({ |m| var v = m.value.asInteger; ~updateParam.(\inStereo, v) });
            nextY = nextY + rowH;

            grp = CompositeView(ctrlView, Rect(8, nextY, ctrlW-16, rowH));
            StaticText(grp, Rect(0, 0, labW, 16)).string_("Input L").stringColor_(Color.white).font_(fLbl);
            nbL = NumberBox(grp, Rect(labW+6, -2, nbW, btnH))
                .value_((~params[\inChanL] ? 0).asInteger)
                .action_({ |nb| var v = nb.value.clip(0,63).round(1).asInteger; nb.value = v; ~updateParam.(\inChanL, v) });
            nextY = nextY + rowH;

            grp = CompositeView(ctrlView, Rect(8, nextY, ctrlW-16, rowH));
            StaticText(grp, Rect(0, 0, labW, 16)).string_("Input R").stringColor_(Color.white).font_(fLbl);
            nbR = NumberBox(grp, Rect(labW+6, -2, nbW, btnH))
                .value_((~params[\inChanR] ? 1).asInteger)
                .action_({ |nb| var v = nb.value.clip(0,63).round(1).asInteger; nb.value = v; ~updateParam.(\inChanR, v) });
            nextY = nextY + rowH;
        }.();

        mkRow.( "FB Amount",      0,0.999,0.95,0.001,3,\fbAmt);
        mkRow.( "FB Delay (s)",   0.0005,10.0,0.03,0.0001,4,\fbDelay);
        mkRow.( "FB Drive",       0,1,0.2,0.001,3,\fbDrive);
        mkRow.( "FB Noise",       0,0.01,0.0005,0.0001,4,\fbNoise);

        mkRecordBlock.();

        mkADSRGrid.();
        mkEnvLPFBlock.();

        sliders = Array.fill(maxPartials,{nil});
        buttons = Array.fill(maxPartials,{nil});
        maxPartials.do({ |i|
            var comp, sl, b;
            comp = CompositeView(gridView,Rect(0,0,btnW,slH+btnH+4));
            sl = Slider(comp,Rect((btnW-slW)/2,2,slW,slH-4))
                .orientation_(\vertical).value_(gainArray[i])
                .action_({|sld| setGainAt.(i,sld.value)});
            sliders[i]=sl;
            b = Button(comp,Rect(0,slH+4,btnW,btnH))
                .states_([[(" "+(i+1)).asString,Color.white,Color.new255(60,66,72)],[(" "+(i+1)).asString,Color.white,Color.new255(56,170,188)]])
                .value_(maskArray[i])
                .action_({|but| setMaskAt.(i,but.value)});
            buttons[i]=b;
        });

        CompositeView(gridView,Rect(0,0,gridView.bounds.width-40,1));
        Button(gridView,Rect(0,0,74,20)).states_([["All on", Color.white, Color.gray(0.18)]])
            .action_({
                setAllMasks.(1);
                ~updateParam.(\mask, maskArray);
                refreshButtons.(buttons);
            });
        Button(gridView,Rect(0,0,74,20)).states_([["All off", Color.white, Color.gray(0.18)]])
            .action_({
                setAllMasks.(0);
                maskArray[0] = 1;
                ~updateParam.(\mask, maskArray);
                refreshButtons.(buttons);
            });
        Button(gridView,Rect(0,0,88,20)).states_([["Primes", Color.white, Color.gray(0.18)]])
            .action_({
                var primes = [2,3,5,7,11,13,17,19,23,29,31];
                setAllMasks.(0); primes.do{|p| if(p<=maxPartials){maskArray[p-1]=1}};
                maskArray[0]=1; ~updateParam.(\mask,maskArray); refreshButtons.(buttons);
            });
        Button(gridView,Rect(0,0,74,20)).states_([["Odds", Color.white, Color.gray(0.18)]])
            .action_({
                setAllMasks.(0); maxPartials.do{|ii| if(((ii+1)%2)==1){maskArray[ii]=1}};
                ~updateParam.(\mask,maskArray); refreshButtons.(buttons);
            });
        Button(gridView,Rect(0,0,74,20)).states_([["Evens", Color.white, Color.gray(0.18)]])
            .action_({
                setAllMasks.(0); maxPartials.do{|ii| if(((ii+1)%2)==0){maskArray[ii]=1}};
                ~updateParam.(\mask,maskArray); refreshButtons.(buttons);
            });

        mkArpBlock.();
        mkFXBlock.();

        mkInputDeviceBlock.();
        mkDeviceBlock.();

        AppClock.sched(0.2, { ~allNotesOff.(); nil });

        win.onClose_({
            ~panic.();
            if(~arpRoutine.notNil) {
                ~arpRoutine.stop;
                ~arpRoutine = nil;
            };
            if(~fxSynth.notNil) { ~fxSynth.free };
            if(~meterSynth.notNil) { ~meterSynth.free };
            if(~meterBus.notNil) { ~meterBus.free; ~meterBus = nil; };
            if(~meterRoutine.notNil) { ~meterRoutine.stop; ~meterRoutine = nil; };
            if(buf.notNil and: {buf!==monoSilence}) { buf.free };
            monoSilence.free;

            ~stopRecordingSafe.();
            ~recorder = nil;
        });
    });
});
)
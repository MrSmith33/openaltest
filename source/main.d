/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module main;

import std.stdio;

import audio;
import stream;
import synth;

import test;

void main()
{
	AudioContext audioContext;
	audioContext.init();
	scope(exit) audioContext.release();

	StreamParams params = {
		freq:44_100,
		numBuffers:3,
		bufferLength:1024,
		totalSamples:44_100*5,
		sleepMsecs:20,
		volume:0.5};

	float nextSample(size_t t)
	{
		return sin!(44_100, 440)(t)
			* fadeOut!(44_100, 100)(t - 64000)
			* fadeIn!(44_100, 100)(t - 32000);
	}

	writeln("Test: synth");
	playGeneratedStream(params, &nextSample);
	writeln("Test: wav");
	testPlaySound("test.wav");
	writeln("Test: stream, 30 sec");
	testGeneratedStream();
}

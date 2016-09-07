/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module main;

import std.stdio : writefln;
import audio : AudioContext, listCaptureDevices, loadOpenAL;
import test;

void main()
{
	loadOpenAL();

	AudioContext audioContext;
	audioContext.init();
	scope(exit) audioContext.release();

	listCaptureDevices();

	writefln("Test: capture");
	testCapture();

	writefln("Test: wav");
	testPlaySound("test.wav");

	// fixed size stream
	writefln("Test: synth");
	testSynth();

	enum SECONDS = 20;
	writefln("Test: stream, %s sec", SECONDS);
	testGeneratedStream(SECONDS);
}

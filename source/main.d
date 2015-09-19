module main;

import audio;
import stream;
import synth;

void main()
{
	AudioContext audioContext;
    audioContext.init();
	scope(exit) audioContext.release();

	import test;
	testPlaySound();
	testGeneratedStream();
}

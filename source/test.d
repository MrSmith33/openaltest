/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module test;

import core.thread : Thread, msecs;
import std.string : fromStringz;
import std.stdio : writefln;

import audio;
import stream;
import synth;
import capture;
import wav;

void testCapture()
{
	enum freq = 24000;
	enum samplesToRecord = 48000;
	enum userBufferSize = FileWriter.CAPACITY / float.sizeof;
	enum deviceBufferSize = userBufferSize * 2;
	enum sleepMsecs = 10;
	enum numChannels = 1;

	size_t samplesRecorded;
	float[userBufferSize] consumerBuffer;

	WavStreamWriter writer;
	writer.open("capture.wav");
	scope(exit) writer.close();

	writer.writeHeader(freq, numChannels);

	bool consumer(float[] samples)
	{
		samplesRecorded += samples.length;
		writefln("recorded %s of %s samples", samplesRecorded, samplesToRecord);

		if (samplesRecorded < samplesToRecord)
		{
			writer.writeChunk(samples);
			return true; // continue
		}
		else
		{
			writer.writeChunk(samples[0..$-(samplesRecorded - samplesToRecord)]);
			return false; // stop capturing
		}
	}

	captureStream(deviceBufferSize, consumerBuffer[], freq, sleepMsecs, &consumer);
}

void testPlaySound(string filename)
{
	Source source;
	source.init();
	scope(exit) source.release();

	Buffer buffer = loadWav(filename);
	scope(exit) buffer.release();

	source.attachBuffer(buffer);
	source.play();
	Thread.sleep(1000.msecs);
	source.stop();
	source.detachBuffer();
}

void testSynth()
{
	StreamParams params = {
		freq:44_100,
		numBuffers:3,
		bufferLength:1024,
		totalSamples:44_100*5,
		sleepMsecs:20,
		volume:0.5};

	float nextSample(size_t t)
	{
		return synth.sin!(44_100, 440)(t)
			* fadeOut!(44_100, 100)(t - 64000)
			* fadeIn!(44_100, 100)(t - 32000);
	}

	playGeneratedStream(params, &nextSample);
}

void testGeneratedStream(size_t seconds)
{
	enum FREQ = 8000;
	StreamParams params = {freq:FREQ, numBuffers:3,
		bufferLength:128, totalSamples:FREQ * seconds, sleepMsecs:16};
	playGeneratedStream(params,
		delegate float(size_t t){return cast(float)gen(t) / 255;});
}

// Music code taken from:
// https://gist.github.com/Eiyeron/7986703
// Long Line Theory, finally in C.
// Enjoy one the best bytebeat directly from your terminal without Javascript!

T min(T)(T a, T b) {return a < b ? a : b;}
T max(T)(T a, T b) {return a > b ? a : b;}

double sb, y, h, a, d, g;

int[] backgroundWaveNotes = [ 15, 15, 23, 8 ];
double[16][2] mainInstrumentNotes =
[
	[15, 18, 17, 17, 17, 17, 999, 999, 22, 22, 999, 18, 999, 15, 20, 22],
	[20, 18, 17, 17, 10, 10, 999, 999, 20, 22,  20, 18,  17, 18, 17, 10]
];

// Single sample generator.
ubyte gen(size_t t)
{
	import std.math;

	sb = (t > 0xffff ? 1 : 0);

	y = pow(2, backgroundWaveNotes[t >> 14 & 3] / 12.);

	a = 1. - ((t & 0x7ff) / cast(double) 0x7ff);
	d = ((cast(int) 14. * t * t ^ t) & 0x7ff);

	g = cast(double) (t & 0x7ff) / cast(double) 0x7ff;
	g = 1. - (g * g);

	h = pow(2.,
	mainInstrumentNotes[((t >> 14 & 3) > 2 ? 1 : 0) & 1][t >> 10 & 15] / 12);

	double wave = (cast(int) (y * t * 0.241) & 127 - 64)
	+ (cast(int) (y * t * 0.25) & 127 - 64) * 1.2;
	double drum = (

	(cast(int) ((cast(int) (5. * t) & 0x7ff) * a) & 255 - 127)
	* ((0x53232323 >> (t >> 11 & 31)) & 1) * a * 1.0

	+ (cast(int) (d * a) & 255 - 128)
	* ((0xa444c444 >> (t >> 11 & 31)) & 1) * a * 1.5 + (cast(int) ((a
	* a * d * (t >> 9 & 1))) & 0xff - 0x80) * 0.1337)
	* sb;

	double instrument =

	((cast(int) (h * t) & 31) + (cast(int) (h * t * 1.992) & 31)
	+ (cast(int) (h * t * .497) & 31) + (cast(int) (h * t * 0.977) & 31))
	* g * sb;

	return cast(ubyte)(max(min((wave + drum + instrument) / 3., 127), -128));
}

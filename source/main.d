
/++
	This is an example project that shows basic use of OpenAL library for sound output
	and wave-d library for loading wav files.
	Start looking at main function and follow the flow of execution.

Important notes:
	* alListenerfv(AL_ORIENTATION...)	needs to be fv, not 3f.
	* streamBuffers need to be attached to source (with alSourcei(source, AL_BUFFER, buffer))
	  after loading its data (with alBufferData)
	* delete source first then buffer.
	  I.e. detach buffer from source before deleting
++/

import std.stdio;
import std.conv : to;
import core.thread;

import derelict.openal.al;
import waved;
import audio;

void main()
{
	SoundSystem soundSystem;
    soundSystem.init();

	Source source;
	source.init();

	Buffer buffer = loadWav("endturn.wav");

    playSound(buffer, source);
	Thread.sleep(1000.msecs);
    playStream(source);
    soundSystem.release();
}

BufferFormat getFormatFromInfo(uint channels)
{
	if (channels == 1)
		return BufferFormat.MONO_FLOAT;
	return BufferFormat.STEREO_FLOAT;
}

void printSoundInfo(ref Sound sound)
{
	writefln("channels = %s", sound.numChannels);
    writefln("samplerate = %s", sound.sampleRate);
    writefln("samples = %s", sound.data.length);
    writefln("lengthInFrames = %s", sound.lengthInFrames);
    writefln("lengthInSeconds = %s", sound.lengthInSeconds);
}

// Music code taken from:
// https://gist.github.com/Eiyeron/7986703
// Long Line Theory, finally in C.
// Enjoy one the best bytebeat directly from your terminal without Javascript!

T min(T)(T a, T b) {return (a) < (b) ? (a) : (b);}
T max(T)(T a, T b) {return (a) > (b) ? (a) : (b);}

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
	 
	return to!ubyte(max(min((wave + drum + instrument) / 3., 127), -128));
}

// Function to load wav sound. wave-d used here.
// Sound is loaded in soundBuffer.
Buffer loadWav(string soundName)
{
	// Load wav file
	Sound sound = decodeWAV(soundName);
	// Lets print some info
    printSoundInfo(sound);
    Buffer buffer;
    buffer.init();
    buffer.loadData(getFormatFromInfo(sound.numChannels), cast(ubyte[])sound.data, sound.sampleRate);
    return buffer;
}

// Function to play sound from given buffer.
// Plays it on 'source' source.
void playSound(Buffer buffer, Source source)
{
	source.attachBuffer(buffer);
	source.play();
}

// Stream player function.
// Fills buffers first and then loops
// and fills used buffers to keep stream playing.
void playStream(ref Source source)
{
	// Stream parameters.
	enum numBuffers = 3;
	enum freq = 8000;
	enum secFrac = 500;
	//enum sampleLength = freq / secFrac;
	enum sampleLength = 100;
	enum uint sampleMsecs = (sampleLength * 1000) / freq;

	Buffer[numBuffers] streamBuffers;
	streamBuffers.init();

	ubyte[sampleLength] sampleBuffer;

	// Detach buffer of previos sound.
	source.detachBuffer();

	// Sample index passed to generator.
	size_t t;

	// Buffer fill function.
	void fillBuffer(Buffer bufferToFill)
	{
		// Generate each sample.
		foreach(ref sample; sampleBuffer)
		{
			sample = gen(t);
			t++;
		}

		// Load data into buffer
		bufferToFill.loadData(BufferFormat.MONO_UBYTE, sampleBuffer, freq);
	}

	foreach(buffer; streamBuffers) {
		fillBuffer(buffer);
		source.queueBuffer(buffer);
	}

	// Play sound
	source.play();
	scope(exit) {
		// Stop sound if user presses enter
		source.stop();
		source.detachBuffer();
		streamBuffers.release();
	}

	Buffer[numBuffers] buffers;
	while(true) {
		Thread.sleep(sampleMsecs.msecs);

		Buffer[] processedBuffers = source.unqueueProcessedBuffers(buffers);

		foreach(buffer; processedBuffers)
		{
			fillBuffer(buffer);
			source.queueBuffer(buffer);
		}

		if(source.state != SourceState.playing)
			source.play();
	}
}
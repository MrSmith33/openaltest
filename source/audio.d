/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module audio;

import std.stdio : writefln;
import std.string : fromStringz;
import derelict.openal.al;

void loadOpenAL() {
	DerelictAL.load();
}

struct AudioContext
{
	ALCdevice* device;
	ALCcontext* context;

	void init() {
		// Open sound device
		device = alcOpenDevice(null);
		assert(device, "Cannot open sound device");
		checkALC(context);

		// Create context
		context = alcCreateContext(device, null);
		assert(context, "Cannot create sound context");
		checkALC(context);

		// Enable context
		alcMakeContextCurrent(context);
		checkALC(context);

		// Setup listener
		alListener3f(AL_POSITION, 0, 0, 0);
		checkAL;
		alListener3f(AL_VELOCITY, 0, 0, 0);
		checkAL;
		alListenerfv(AL_ORIENTATION, [0f, 0, -1, 0, 1, 0].ptr);
		checkAL;
	}

	// Free all resources.
	void release() {
		alcMakeContextCurrent(null);
		checkALC(context);
		alcDestroyContext(context);
		checkALC(context);
		alcCloseDevice(device);
		checkALC(context);
	}
}

void checkALC(ALCcontext* context, string file = __FILE__, size_t line = __LINE__)
{
	auto error = alcGetError(context);
	if (error != ALC_NO_ERROR)
		throw new Error(alcErrorMessage[error], file, line);
}

enum SourceState : int
{
	initial = AL_INITIAL,
	playing  = AL_PLAYING,
	paused = AL_PAUSED,
	stopped = AL_STOPPED,
}

struct Source
{
	uint id;

	void init() {
		// Create source
		alGenSources(1, &id);
		checkAL;

		// Setup source
		// Set sound speed to 100%
		alSourcef(id, AL_PITCH, 1.0);
		checkAL;
		// Set sound volume to 100%.
		alSourcef(id, AL_GAIN, 1.0);
		checkAL;
		// Position of the sound source in 3d space
		alSource3f(id, AL_POSITION, 0, 0, 0);
		checkAL;
		// Velocity of the sound source.
		alSource3f(id, AL_VELOCITY, 0, 0, 0);
		checkAL;
		// Play sound once
		alSourcei(id, AL_LOOPING, AL_FALSE);
		checkAL;
	}

	void release() {
		alDeleteSources(1, &id);
		checkAL;
	}

	void attachBuffer(Buffer buf) {
		alSourcei(id, AL_BUFFER, buf.id);
		checkAL;
	}

	void detachBuffer() {
		alSourcei(id, AL_BUFFER, 0);
		checkAL;
	}

	// A source that will be used for streaming should not have
	// its first buffer attached using attachBuffer.
	// Use detachBuffer before streaming.
	// All buffers attached to using queueBuffer should have the same audio format.
	void queueBuffer(Buffer buf) {
		alSourceQueueBuffers(id, 1, &buf.id);
		checkAL;
	}

	// returned array is a slice of buffers parameter filled with unqueued buffers.
	// buffers should be big enough to hold all processed buffers.
	// Buffers that were not returned will be returned in later calls.
	// Check numBuffersProcessed to know how many buffers is needed.
	Buffer[] unqueueProcessedBuffers(Buffer[] buffers) {
		int numBuffers = 0;
		alGetSourcei(id, AL_BUFFERS_PROCESSED, &numBuffers);
		checkAL;
		numBuffers = cast(int)(buffers.length < numBuffers ? buffers.length : numBuffers);
		buffers = buffers[0..numBuffers];
		foreach(ref buffer; buffers) {
			alSourceUnqueueBuffers(id, 1, &buffer.id);
			checkAL;
		}
		return buffers;
	}

	void play() {
		alSourcePlay(id);
		checkAL;
	}

	void pause() {
		alSourcePause(id);
		checkAL;
	}

	void stop() {
		alSourceStop(id);
		checkAL;
	}

	void rewind() {
		alSourceRewind(id);
		checkAL;
	}

	SourceState state() @property {
		int state;
		alGetSourcei(id, AL_SOURCE_STATE, &state);
		checkAL;
		return cast(SourceState) state;
	}

	int numBuffersQueued() @property {
		int numQueued;
		alGetSourcei(id, AL_BUFFERS_QUEUED, &numQueued);
		checkAL;
		return numQueued;
	}

	int numBuffersProcessed() @property {
		int numQueued;
		alGetSourcei(id, AL_BUFFERS_PROCESSED, &numQueued);
		checkAL;
		return numQueued;
	}

	float gain(float gain_) @property {
		alSourcef(id, AL_GAIN, gain_);
		checkAL;
		return gain_;
	}
}

struct CaptureDevice
{
	ALCdevice* device;

	static const(char)* defaultDeviceName() {
		auto name = alcGetString(null, ALC_CAPTURE_DEFAULT_DEVICE_SPECIFIER);
		checkAL;
		return name;
	}

	const(char)[] name() {
		auto str = alcGetString(device, ALC_CAPTURE_DEVICE_SPECIFIER);
		checkAL;
		return str.fromStringz;
	}

	bool open(const(char)* deviceName, size_t frequency, BufferFormat format, size_t bufferSize) {
		device = alcCaptureOpenDevice(deviceName, cast(uint)frequency, cast(int)format, cast(int)bufferSize);
		checkAL;
		return device !is null;
	}

	void close() {
		alcCaptureCloseDevice(device);
		checkAL;
	}

	void startCapture() {
		alcCaptureStart(device);
		checkAL;
	}

	void stopCapture() {
		alcCaptureStop(device);
		checkAL;
	}

	void captureSamples(T)(T[] buffer) {
		alcCaptureSamples(device, cast(void*)buffer.ptr, cast(int)buffer.length);
		checkAL;
	}

	size_t samplesAvailable() {
		int capturedSamples;
		alcGetIntegerv(device, ALC_CAPTURE_SAMPLES, 1, &capturedSamples);
		checkAL;
		return capturedSamples;
	}
}

void listCaptureDevices()
{
	import derelict.openal.al;

	const(char)* devList = alcGetString(null, ALC_CAPTURE_DEVICE_SPECIFIER);

	if (devList)
	{
		writefln("Available Capture Devices are:");

		size_t i = 1;
		while (*devList)
		{
			const(char)[] devName = fromStringz(devList);
			writefln("%s. %s", i, devName);
			devList += devName.length + 1;
			++i;
		}
	}
}

enum BufferFormat : int
{
	MONO_8 = AL_FORMAT_MONO8,
	MONO_16 = AL_FORMAT_MONO16,
	STEREO_8 = AL_FORMAT_STEREO8,
	STEREO_16 = AL_FORMAT_STEREO16,
	MONO_FLOAT = AL_FORMAT_MONO_FLOAT32,
	STEREO_FLOAT = AL_FORMAT_STEREO_FLOAT32,
}

struct Buffer
{
	uint id;

	void init() {
		assert(id == 0, "Initializing already initialized buffer");
		alGenBuffers(1, &id);
		checkAL;
	}

	// A buffer which is attached to a source can not be deleted
	void release() {
		alDeleteBuffers(1, &id);
		id = 0;
	}

	void loadData(BufferFormat format, ubyte[] data, size_t frequency) {
		alBufferData(id, format, data.ptr, cast(int)data.length, cast(int)frequency);
		checkAL;
	}
}

// Function to load wav sound. wave-d used here.
// Sound is loaded in soundBuffer.
Buffer loadWav(string soundName)
{
	import wav;
	Sound sound = decodeWAV(soundName);
	Buffer buffer;
	buffer.init();
	BufferFormat fmt = sound.numChannels == 1 ?
		BufferFormat.MONO_FLOAT : BufferFormat.STEREO_FLOAT;

	buffer.loadData(fmt, cast(ubyte[])sound.data, sound.sampleRate);
	return buffer;
}

// Convenience method for initialization of multiple buffers
void init(Buffer[] buffers) {
	foreach(ref b; buffers)
		b.init();
}

void release(Buffer[] buffers) {
	foreach(ref b; buffers)
		b.release();
}

void checkAL(string file = __FILE__, size_t line = __LINE__)
{
	import std.string : format;
	auto error = alGetError();
	if (error != AL_NO_ERROR)
		throw new Error(alErrorMessage[error], file, line);
}


string[int] alErrorMessage;
string[int] alcErrorMessage;

static this() {
	alErrorMessage =
	[AL_NO_ERROR : "AL error: There is no current error",
	 AL_INVALID_NAME : "AL error: Invalid name parameter",
	 AL_INVALID_ENUM : "AL error: Invalid enum parameter",
	 AL_INVALID_VALUE : "AL error: Invalid value",
	 AL_INVALID_OPERATION : "AL error: invalid operation",
	 AL_OUT_OF_MEMORY : "AL error: Unable to allocate memory"];
	alcErrorMessage =
	[ALC_NO_ERROR : "(ALC) There is no current error",
	 ALC_INVALID_DEVICE : "(ALC) Invalid device specifier",
	 ALC_INVALID_CONTEXT : "(ALC) Invalid context specifier",
	 ALC_INVALID_ENUM : "(ALC) Invalid enum parameter value",
	 ALC_INVALID_VALUE : "(ALC) Invalid value",
	 ALC_OUT_OF_MEMORY : "(ALC) Unable to allocate memory"];
}

// Wave-d http://github.com/d-gamedev-team/wave-d/
module wav;

import std.array;
import std.file;
import std.format;
import std.range;
import std.string;
import std.traits;
import std.stdio : File;

/// Supports Microsoft WAV audio file format.


// wFormatTag
immutable int LinearPCM = 0x0001;
immutable int FloatingPointIEEE = 0x0003;
immutable int WAVE_FORMAT_EXTENSIBLE = 0xFFFE;


/// Decodes a WAV file.
/// Throws: WavedException on error.
Sound decodeWAV(string filepath)
{
	auto bytes = cast(ubyte[]) std.file.read(filepath);
	return decodeWAV(bytes);
}

/// Encodes a WAV file.
/// Throws: WavedException on error.
void encodeWAV(Sound sound, string filepath)
{
	auto output = appender!(ubyte[])();
	output.encodeWAV(sound);
	std.file.write(filepath, output.data);
}

/// Decodes a WAV.
/// Throws: WavedException on error.
Sound decodeWAV(R)(R input) if (isInputRange!R)
{
	// check RIFF header
	{
		uint chunkId, chunkSize;
		getRIFFChunkHeader(input, chunkId, chunkSize);
		if (chunkId != RIFFChunkId!"RIFF")
			throw new WavedException("Expected RIFF chunk.");

		if (chunkSize < 4)
			throw new WavedException("RIFF chunk is too small to contain a format.");

		if (popBE!uint(input) !=  RIFFChunkId!"WAVE")
			throw new WavedException("Expected WAVE format.");
	}

	bool foundFmt = false;
	bool foundData = false;


	int audioFormat;
	int numChannels;
	int sampleRate;
	int byteRate;
	int blockAlign;
	int bitsPerSample;

	Sound result;

	// while chunk is not
	while (!input.empty)
	{
		uint chunkId, chunkSize;
		getRIFFChunkHeader(input, chunkId, chunkSize);
		if (chunkId == RIFFChunkId!"fmt ")
		{
			if (foundFmt)
				throw new WavedException("Found several 'fmt ' chunks in RIFF file.");

			foundFmt = true;

			if (chunkSize < 16)
				throw new WavedException("Expected at least 16 bytes in 'fmt ' chunk."); // found in real-world for the moment: 16 or 40 bytes

			audioFormat = popLE!ushort(input);
			if (audioFormat == WAVE_FORMAT_EXTENSIBLE)
				throw new WavedException("No support for format WAVE_FORMAT_EXTENSIBLE yet."); // Reference: http://msdn.microsoft.com/en-us/windows/hardware/gg463006.aspx

			if (audioFormat != LinearPCM && audioFormat != FloatingPointIEEE)
				throw new WavedException(format("Unsupported audio format %s, only PCM and IEEE float are supported.", audioFormat));

			numChannels = popLE!ushort(input);

			sampleRate = popLE!uint(input);
			if (sampleRate <= 0)
				throw new WavedException(format("Unsupported sample-rate %s.", cast(uint)sampleRate)); // we do not support sample-rate higher than 2^31hz

			uint bytesPerSec = popLE!uint(input);
			int bytesPerFrame = popLE!ushort(input);
			bitsPerSample = popLE!ushort(input);

			if (bitsPerSample != 8 && bitsPerSample != 16 && bitsPerSample != 24 && bitsPerSample != 32)
				throw new WavedException(format("Unsupported bitdepth %s.", cast(uint)bitsPerSample));

			if (bytesPerFrame != (bitsPerSample / 8) * numChannels)
				throw new WavedException("Invalid bytes-per-second, data might be corrupted.");

			skipBytes(input, chunkSize - 16);
		}
		else if (chunkId == RIFFChunkId!"data")
		{
			if (foundData)
				throw new WavedException("Found several 'data' chunks in RIFF file.");

			if (!foundFmt)
				throw new WavedException("'fmt ' chunk expected before the 'data' chunk.");

			int bytePerSample = bitsPerSample / 8;
			uint frameSize = numChannels * bytePerSample;
			if (chunkSize % frameSize != 0)
				throw new WavedException("Remaining bytes in 'data' chunk, inconsistent with audio data type.");

			uint numFrames = chunkSize / frameSize;
			uint numSamples = numFrames * numChannels;

			result.data.length = numSamples;

			if (audioFormat == FloatingPointIEEE)
			{
				if (bytePerSample == 4)
				{
					for (uint i = 0; i < numSamples; ++i)
						result.data[i] = popFloatLE(input);
				}
				else if (bytePerSample == 8)
				{
					for (uint i = 0; i < numSamples; ++i)
						result.data[i] = popDoubleLE(input);
				}
				else
					throw new WavedException("Unsupported bit-depth for floating point data, should be 32 or 64.");
			}
			else if (audioFormat == LinearPCM)
			{
				if (bytePerSample == 1)
				{
					for (uint i = 0; i < numSamples; ++i)
					{
						ubyte b = popUbyte(input);
						result.data[i] = (b - 128) / 127.0;
					}
				}
				else if (bytePerSample == 2)
				{
					for (uint i = 0; i < numSamples; ++i)
					{
						int s = popLE!short(input);
						result.data[i] = s / 32767.0;
					}
				}
				else if (bytePerSample == 3)
				{
					for (uint i = 0; i < numSamples; ++i)
					{
						int s = pop24bitsLE!R(input);
						result.data[i] = s / 8388607.0;
					}
				}
				else if (bytePerSample == 4)
				{
					for (uint i = 0; i < numSamples; ++i)
					{
						int s = popLE!int(input);
						result.data[i] = s / 2147483648.0;
					}
				}
				else
					throw new WavedException("Unsupported bit-depth for integer PCM data, should be 8, 16, 24 or 32 bits.");
			}
			else
				assert(false); // should have been handled earlier, crash

			foundData = true;
		}
		else
		{
			// ignore unrecognized chunks
			skipBytes(input, chunkSize);
		}
	}

	if (!foundFmt)
		throw new WavedException("'fmt ' chunk not found.");

	if (!foundData)
		throw new WavedException("'data' chunk not found.");


	result.numChannels = numChannels;
	result.sampleRate = sampleRate;

	return result;
}

struct WavStreamWriter
{
	File file;
	FileWriter writer;
	size_t totalSamples;
	int sampleRate;
	int numChannels;

	void open(string fileName)
	{
		file.open(fileName, "wb+");
	}

	void writeHeader(int sampleRate, int numChannels)
	{
		this.sampleRate = sampleRate;
		this.numChannels = numChannels;
		writer = FileWriter(file);
		writer.put = encodeWAVHeader(sampleRate, numChannels, 0);
		encodeWAVDataHeader(writer, 0);
	}

	void writeChunk(float[] data)
	{
		encodeWAVDataSamples(writer, data);
		totalSamples += data.length;
	}

	void close() {
		writer.flush();
		fixNumSamples();
		file.close();
	}

	void fixNumSamples() {
		file.seek(0);
		writer = FileWriter(file);
		writer.put(encodeWAVHeader(sampleRate, numChannels, totalSamples)[]);
		encodeWAVDataHeader(writer, totalSamples);
		writer.flush();
	}
}

struct FileWriter
{
	File file;

	enum CAPACITY = 4096;
	ubyte[CAPACITY] buffer;
	size_t length;

	void put(ubyte[] data ...)
	{
		size_t cap = capacity;
		if (data.length > cap)
		{
			size_t writeOffset;

			// fill buffer till CAPACITY
			if (length > 0)
			{
				buffer[length..$] = data[0..cap];
				file.rawWrite(buffer);
				writeOffset = cap;
			}

			size_t writeLength = ((data.length - writeOffset) / CAPACITY) * CAPACITY;
			size_t writeTo = writeOffset+writeLength;
			if (writeLength)
				file.rawWrite(data[writeOffset..writeTo]);

			size_t writeLater = data.length - writeTo;
			if (writeLater)
			{
				buffer[0..writeLater] = data[writeTo..$];
				length = writeLater;
			}
			else
			{
				length = 0;
			}
		}
		else
		{
			buffer[length..length+data.length] = data;
			length += data.length;
		}
	}

	void flush() {
		if (length) {
			file.rawWrite(buffer[0..length]);
			length = 0;
		}
	}

	size_t capacity() { return CAPACITY - length; }
}


/// Encodes a WAV.
void encodeWAV(R)(auto ref R output, Sound sound) if (isOutputRange!(R, ubyte))
{
	auto header = encodeWAVHeader(sound.sampleRate, sound.numChannels, sound.data.length);
	output.put(header[]);

	// data sub-chunk
	encodeWAVDataHeader(output, sound.data.length);
	encodeWAVDataSamples(output, sound.data);
}

ubyte[36] encodeWAVHeader(uint sampleRate, uint numChannels, size_t dataLength)
{
	// Avoid a number of edge cases.
	if (numChannels < 0 || numChannels > 1024)
		throw new WavedException(format("Can't save a WAV with %s channels.", numChannels));

	ubyte[36] buffer;
	ubyte[] bufSlice = buffer[];

	// RIFF header
	bufSlice.writeRIFFChunkHeader(RIFFChunkId!"RIFF", 4 + (4 + 4 + 16) + (4 + 4 + float.sizeof * dataLength) );
	bufSlice.writeBE!uint(RIFFChunkId!"WAVE");

	// 'fmt ' sub-chunk
	bufSlice.writeRIFFChunkHeader(RIFFChunkId!"fmt ", 0x10);
	bufSlice.writeLE!ushort(FloatingPointIEEE);

	bufSlice.writeLE!ushort(cast(ushort)(numChannels));
	bufSlice.writeLE!uint(cast(ushort)(sampleRate));

	size_t bytesPerSec = sampleRate * numChannels * float.sizeof;
	bufSlice.writeLE!uint( cast(uint)(bytesPerSec));

	uint bytesPerFrame = cast(uint)(numChannels * float.sizeof);
	bufSlice.writeLE!ushort(cast(ushort)bytesPerFrame);

	bufSlice.writeLE!ushort(32);
	return buffer;
}

void encodeWAVDataHeader(R)(auto ref R output, size_t numSamples)
	if (isOutputRange!(R, ubyte))
{
	writeRIFFChunkHeader(output, RIFFChunkId!"data", float.sizeof * numSamples);
}

void encodeWAVDataSamples(R)(auto ref R output, float[] samples)
	if (isOutputRange!(R, ubyte))
{
	writeFloatLE(output, samples);
}

// Utils

/// The simple structure currently used in wave-d. Expect changes about this.
struct Sound
{
	int sampleRate;  /// Sample rate.
	int numChannels; /// Number of interleaved channels in data.
	float[] data;    /// data layout: machine endianness, interleaved channels. Contains numChannels * lengthInFrames() samples.

	this(int sampleRate, int numChannels, float[] data)
	{
		this.sampleRate = sampleRate;
		this.numChannels = numChannels;
		this.data = data;
	}

	/// Returns: Length in number of frames.
	int lengthInFrames() pure const nothrow
	{
		return cast(int)(data.length) / numChannels;
	}

	/// Returns: Length in seconds.
	double lengthInSeconds() pure const nothrow
	{
		return lengthInFrames() / cast(double)sampleRate;
	}
}

/// The one type of Exception thrown in this library
final class WavedException : Exception
{
	@safe pure nothrow this(string message, string file =__FILE__, size_t line = __LINE__, Throwable next = null)
	{
		super(message, file, line, next);
	}
}


private template IntegerLargerThan(int numBytes) if (numBytes >= 1 && numBytes <= 8)
{
	static if (numBytes == 1)
		alias IntegerLargerThan = ubyte;
	else static if (numBytes == 2)
		alias IntegerLargerThan = ushort;
	else static if (numBytes <= 4)
		alias IntegerLargerThan = uint;
	else
		alias IntegerLargerThan = ulong;
}

ubyte popUbyte(R)(ref R input) if (isInputRange!R)
{
	if (input.empty)
		throw new WavedException("Expected a byte, but end-of-input found.");

	ubyte b = input.front;
	input.popFront();
	return b;
}

void skipBytes(R)(ref R input, int numBytes) if (isInputRange!R)
{
	for (int i = 0; i < numBytes; ++i)
		popUbyte(input);
}

// Generic integer parsing
auto popInteger(R, int NumBytes, bool WantSigned, bool LittleEndian)(ref R input) if (isInputRange!R)
{
	alias T = IntegerLargerThan!NumBytes;

	T result = 0;

	static if (LittleEndian)
	{
		for (int i = 0; i < NumBytes; ++i)
			result |= ( cast(T)(popUbyte(input)) << (8 * i) );
	}
	else
	{
		for (int i = 0; i < NumBytes; ++i)
			result = (result << 8) | popUbyte(input);
	}

	static if (WantSigned)
	{
		// make sure the sign bit is extended to the top in case of a larger result value
		Signed!T signedResult = cast(Signed!T)result;
		enum bits = 8 * (T.sizeof - NumBytes);
		static if (bits > 0)
		{
			signedResult = signedResult << bits;
			signedResult = signedResult >> bits; // signed right shift, replicates sign bit
		}
		return signedResult;
	}
	else
		return result;
}

// Generic integer writing
void writeInteger(R, int NumBytes, bool LittleEndian)(ref R output, IntegerLargerThan!NumBytes n) if (isOutputRange!(R, ubyte))
{
	alias T = IntegerLargerThan!NumBytes;

	auto u = cast(Unsigned!T)n;

	static if (LittleEndian)
	{
		for (int i = 0; i < NumBytes; ++i)
		{
			ubyte b = (u >> (i * 8)) & 255;
			output.put(b);
		}
	}
	else
	{
		for (int i = 0; i < NumBytes; ++i)
		{
			ubyte b = (u >> ( (NumBytes - 1 - i) * 8) ) & 255;
			output.put(b);
		}
	}
}

// Reads a big endian integer from input.
T popBE(T, R)(ref R input) if (isInputRange!R)
{
	return popInteger!(R, T.sizeof, isSigned!T, false)(input);
}

// Reads a little endian integer from input.
T popLE(T, R)(ref R input) if (isInputRange!R)
{
	return popInteger!(R, T.sizeof, isSigned!T, true)(input);
}

// Writes a big endian integer to output.
void writeBE(T, R)(ref R output, T n) if (isOutputRange!(R, ubyte))
{
	writeInteger!(R, T.sizeof, false)(output, n);
}

// Writes a little endian integer to output.
void writeLE(T, R)(ref R output, T n) if (isOutputRange!(R, ubyte))
{
	writeInteger!(R, T.sizeof, true)(output, n);
}


alias pop24bitsLE(R) = popInteger!(R, 3, true, true);


// read/write 32-bits float

union float_uint
{
	float f;
	uint i;
}

float popFloatLE(R)(ref R input) if (isInputRange!R)
{
	float_uint fi;
	fi.i = popLE!uint(input);
	return fi.f;
}

void writeFloatLE(R)(ref R output, float x) if (isOutputRange!(R, ubyte))
{
	float_uint fi;
	fi.f = x;
	writeLE!uint(output, fi.i);
}

void writeFloatLE(R)(ref R output, float[] data) if (isOutputRange!(R, ubyte))
{
	version(LittleEndian)
	{
		output.put(cast(ubyte[])data);
	}
	else
	{
		foreach (float f; data)
			output.writeFloatLE(f);
	}
}


// read/write 64-bits float

union double_ulong
{
	double d;
	ulong i;
}

float popDoubleLE(R)(ref R input) if (isInputRange!R)
{
	double_ulong du;
	du.i = popLE!ulong(input);
	return du.d;
}

void writeDoubleLE(R)(ref R output, double x) if (isOutputRange!(R, ubyte))
{
	double_ulong du;
	du.d = x;
	writeLE!ulong(output, du.i);
}

// Reads RIFF chunk header.
void getRIFFChunkHeader(R)(ref R input, out uint chunkId, out uint chunkSize) if (isInputRange!R)
{
	chunkId = popBE!uint(input);
	chunkSize = popLE!uint(input);
}

// Writes RIFF chunk header (you have to count size manually for now...).
void writeRIFFChunkHeader(R)(ref R output, uint chunkId, size_t chunkSize) if (isOutputRange!(R, ubyte))
{
	writeBE!uint(output, cast(uint)(chunkId));
	writeLE!uint(output, cast(uint)(chunkSize));
}

template RIFFChunkId(string id)
{
	static assert(id.length == 4);
	uint RIFFChunkId = (cast(ubyte)(id[0]) << 24)
					 | (cast(ubyte)(id[1]) << 16)
					 | (cast(ubyte)(id[2]) << 8)
					 | (cast(ubyte)(id[3]));
}


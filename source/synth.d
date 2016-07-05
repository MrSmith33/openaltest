module synth;

struct SampleGenerator(float delegate(size_t) generator)
{
	size_t t;

	float next() {
		float sample = generator(t);
		++t;
		return sample;
	}
}

struct DynSampleGenerator
{
	float delegate(size_t) generator;
	size_t t;

	float next() {
		float sample = generator(t);
		++t;
		return sample;
	}
}

// sound generation

import std.math : cos, sin, PI;

float sin(size_t sampleRate, float sinFrequency)(size_t t)
{
	return sin(t * 2.0 * PI * sinFrequency / sampleRate);
}

float fadeIn(size_t sampleRate, float speed)(ptrdiff_t t)
{
	if (t > 0)
		return 1.0;
	else
	{
		float x = cast(float)t / sampleRate;
		return speed^^x;
	}
}

float fadeOut(size_t sampleRate, float speed)(ptrdiff_t t)
{
	if (t < 0)
		return 1.0;
	else
	{
		float x = cast(float)t / sampleRate;
		return 1.0/(speed^^x);
	}
}

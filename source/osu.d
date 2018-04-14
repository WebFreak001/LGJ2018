module osu;

import std.algorithm;
import std.bitmanip;
import std.conv;
import std.range;
import std.stdio;
import std.string;
import std.traits;

struct HitObject
{
	enum Type : ubyte
	{
		circle,
		slider,
		spinner
	}

	int x, y;
	int time;
	Type type;
	bool newCombo;
	bool holdNote;
	ubyte skipCombos;
	union
	{
		mixin(bitfields!(bool, "soundNormal", 1, bool, "soundWhistle", 1, bool,
				"soundFinish", 1, bool, "soundClap", 1, uint, "", 4));
		ubyte hitSounds;
	}

	alias taikoIsBig = soundFinish;

	bool taikoIsBlue() const @property
	{
		return (hitSounds & 0b1010) != 0;
	}

	auto taikoIsBlue(bool value) @property
	{
		if (value)
			hitSounds |= 0b1000;
		else
			hitSounds &= ~0b1010;
		return value;
	}

	int sampleSet;
	int additionSet;
	int customSampleSetIndex;
	int sampleVolume;
	string sampleFilename;

	// additions for this game
	double spacing = 3;
}

struct Osu
{
	enum Mod : uint
	{
		none = 0,
		ez = 1 << 0,
		nf = 1 << 1,
		ht = 1 << 2,
		hr = 1 << 3,
		sd = 1 << 4,
		pf = 0b11 << 4,
		dt = 1 << 6,
		nc = 0b11 << 6,
		hd = 1 << 8,
		fi = 1 << 9,
		fl = 1 << 10,
		rl = 1 << 11,
		ap = 1 << 12,
		so = 1 << 13,
		at = 1 << 14,
		cm = 1 << 15,
		k1 = 1 << 16,
		k2 = 2 << 16,
		k3 = 3 << 16,
		k4 = 4 << 16,
		k5 = 5 << 16,
		k6 = 6 << 16,
		k7 = 7 << 16,
		k8 = 8 << 16,
		k9 = 9 << 16,
		coop = 1 << 20,
		rd = 1 << 21
	}

	enum Mode
	{
		osu,
		taiko,
		ctb,
		mania
	}

	struct General
	{
		@("AudioFilename") string audioFilename;
		@("AudioLeadIn") int audioLeadIn;
		@("PreviewTime") int previewTime;
		@("Countdown") bool countdown;
		@("SampleSet") string sampleSet;
		@("StackLeniency") double stackLeniency;
		@("Mode") Mode mode;
		@("LetterboxInBreaks") bool letterboxInBreaks;
		@("WidescreenStoryboard") bool widescreenStoryboard;
		@("EpilepsyWarning") bool epilepsyWarning;
	}

	struct Editor
	{
		@("Bookmarks", ",") int[] bookmarks;
		@("DistanceSpacing") double distanceSpacing;
		@("BeatDivisor") int beatDivisor;
		@("GridSize") int gridSize;
		@("TimelineZoom") double timelineZoom;
	}

	struct Metadata
	{
		@("Title") string title;
		@("TitleUnicode") string titleUnicode;
		@("Artist") string artist;
		@("ArtistUnicode") string artistUnicode;
		@("Creator") string creator;
		@("Version") string version_;
		@("Source") string source;
		@("Tags", " ") string[] tags;
		@("BeatmapID") int beatmapID;
		@("BeatmapSetID") int beatmapSetID;
	}

	struct Difficulty
	{
		@("HPDrainRate") double hpDrainRate;
		@("CircleSize") double circleSize;
		@("OverallDifficulty") double overallDifficulty;
		@("ApproachRate") double approachRate;
		@("SliderMultiplier") double sliderMultiplier = 1.4;
		@("SliderTickRate") double sliderTickRate = 1;
	}

	struct Events
	{
		void parseLine(string line)
		{

		}
	}

	struct TimingPoints
	{
		void parseLine(string line)
		{

		}
	}

	struct Colours
	{
		void parseLine(string line)
		{

		}
	}

	struct HitObjects
	{
		HitObject[] objects;

		void parseLine(string line)
		{
			auto parts = line.split(',');
			if (parts.length < 5)
				return;
			HitObject obj;
			obj.x = parts[0].to!int;
			obj.y = parts[1].to!int;
			obj.time = parts[2].to!int;
			auto type = parts[3].to!int;
			if (type & 0b0001)
				obj.type = HitObject.type.circle;
			else if (type & 0b0010)
				obj.type = HitObject.type.slider;
			else if (type & 0b1000)
				obj.type = HitObject.type.circle;

			if (type & 0b0100)
				obj.newCombo = true;
			obj.skipCombos = (type >> 4) & 0b111;
			if (type & 0b1000_0000)
				obj.holdNote = true;

			obj.hitSounds = parts[4].to!ubyte;

			int extraIndex;
			if (obj.type == HitObject.Type.circle)
				extraIndex = 5;

			if (extraIndex != 0 && extraIndex < parts.length)
			{
				auto extraParts = parts[extraIndex].split(':');
				if (extraParts.length >= 5)
				{
					obj.sampleSet = extraParts[0].to!int;
					obj.additionSet = extraParts[1].to!int;
					obj.customSampleSetIndex = extraParts[2].to!int;
					obj.sampleVolume = extraParts[3].to!int;
					obj.sampleFilename = extraParts[4 .. $].join(":");
				}
			}
			objects ~= obj;
		}
	}

	// type names are the important part
	General general;
	Editor editor;
	Metadata metadata;
	Difficulty difficulty;
	Events events;
	TimingPoints timingPoints;
	Colours colours;
	HitObjects hitObjects;

	double odWith(Mod mods = Mod.none) @property const
	{
		double od = difficulty.overallDifficulty;
		if (mods & Mod.ez)
			od *= 0.5;
		if (mods & Mod.hr)
			od = min(od * 1.4, 10);
		return od;
	}

	double arWith(Mod mods = Mod.none) @property const
	{
		double ar = difficulty.approachRate;
		if (mods & Mod.ez)
			ar *= 0.5;
		if (mods & Mod.hr)
			ar = min(ar * 1.4, 10);
		return ar;
	}

	double arMsWith(Mod mods = Mod.none) @property const
	{
		double ar = arWith(mods);
		double ms;
		if (ar < 5)
			ms = 1800 - ar * 120;
		else
			ms = 1200 - (ar - 5) * 150;
		if (mods & Mod.dt)
			ms /= 1.5;
		if (mods & Mod.ht)
			ms /= 0.75;
		if (ms < 300)
			return 300;
		else
			return ms;
	}

	float hitMsFor300(Mod mods) @property const
	{
		double od = odWith(mods);
		double ret = 79.5 - od * 6;
		if (mods & Mod.dt)
			ret /= 1.5;
		if (mods & Mod.ht)
			ret /= 0.75;
		return ret;
	}

	float hitMsFor100(Mod mods) @property const
	{
		double od = odWith(mods);
		double ret = 139.5 - od * 8;
		if (mods & Mod.dt)
			ret /= 1.5;
		if (mods & Mod.ht)
			ret /= 0.75;
		return ret;
	}

	float hitMsFor50(Mod mods) @property const
	{
		double od = odWith(mods);
		double ret = 199.5 - od * 10;
		if (mods & Mod.dt)
			ret /= 1.5;
		if (mods & Mod.ht)
			ret /= 0.75;
		return ret;
	}
}

Osu parseOsu(string data)
{
	Osu ret;
	string currentSection;
	foreach (line; data.lineSplitter)
	{
		if (line.startsWith("osu file format") || !line.strip.length)
			continue;
		if (line.startsWith('[') && line.endsWith(']'))
			currentSection = line[1 .. $ - 1].strip;
		else
		{
		SectionSwitch:
			switch (currentSection)
			{
				static foreach (section; FieldNameTuple!Osu)
				{
			case typeof(__traits(getMember, Osu, section)).stringof:
					static if (is(typeof(typeof(__traits(getMember, Osu, section)).parseLine)))
					{
						__traits(getMember, ret, section).parseLine(line);
					}
					else
					{
						auto parts = line.findSplit(":");
						auto key = parts[0];
						auto value = parts[2];
						parseKVPair!section(ret, key, value);
					}
					break SectionSwitch;
				}
			default:
				stderr.writeln("Could not find section ", currentSection);
				break;
			}
		}
	}
	if (!ret.metadata.artistUnicode.length)
		ret.metadata.artistUnicode = ret.metadata.artist;
	if (!ret.metadata.titleUnicode.length)
		ret.metadata.titleUnicode = ret.metadata.title;
	return ret;
}

private void parseKVPair(string section)(ref Osu ret, string key, string value)
{
Switch:
	switch (key)
	{
		static foreach (member; FieldNameTuple!(typeof(__traits(getMember, Osu, section))))
		{
	case __traits(getAttributes, mixin("ret." ~ section ~ "." ~ member))[0]:
			try
			{
				static if (isArray!(typeof(mixin("ret." ~ section ~ "." ~ member)))
						&& !isSomeString!(typeof(mixin("ret." ~ section ~ "." ~ member))))
					mixin("ret." ~ section ~ "." ~ member) = value.split(__traits(getAttributes,
							mixin("ret." ~ section ~ "." ~ member))[1]).convInput!(
							typeof(mixin("ret." ~ section ~ "." ~ member)));
				else
					mixin("ret." ~ section ~ "." ~ member) = value.convInput!(
							typeof(mixin("ret." ~ section ~ "." ~ member)));
			}
			catch (Exception e)
			{
				stderr.writeln("Exception when parsing " ~ section ~ ": ", e);
			}
			break Switch;
		}
	default:
		stderr.writeln("Skipping unknown field ", key);
		break;
	}
}

private T convInput(T)(string value)
{
	value = value.strip;
	static if (is(T == enum))
		return cast(T) value.convInput!(OriginalType!T);
	else static if (is(T : bool))
		return value == "1" || value == "true" || value == "on";
	else
		return value.to!T;
}

private T convInput(T)(string[] values) if (isArray!T)
{
	T ret;
	static if (isStaticArray!T)
	{
		if (values.length != ret.length)
			throw new Exception(
					"Expected " ~ ret.length.to!string ~ " elements, but got " ~ values.length.to!string);
	}
	else
	{
		ret.length = values.length;
	}
	foreach (i, value; values)
	{
		ret[i] = value.convInput!(ElementType!T);
	}
	return ret;
}

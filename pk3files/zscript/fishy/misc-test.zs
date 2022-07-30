class TestSplash : Actor
{
	Default
	{
		+NOINTERACTION;
		+NOBLOCKMAP;
	}

	States
	{
	Spawn:
		SKUL FGHIJK 6;
		Stop;
	}
}

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

class TESTPushable1 : ExplosiveBarrel
{
	Default
	{
		+PUSHABLE;
		PushSound "pain/pain";
		PushFactor 3;
	}
}

class TESTPushable2 : BurningBarrel
{
	Default
	{
		+PUSHABLE;
		PushSound "*usefail";
	}
}

class TESTNoDeathSeq : ZombieMan
{
	Default
	{
		//$Title TESTNoDeathSeq
		+NOICEDEATH;
	}

	States
	{
	Death:
	XDeath:
		Stop;
	}
}

class TESTCustomActorFlagChange : FishyPlatform
{
	Default
	{
		ClearFlags;
	}

	States
	{
	Spawn:
		POSS A 1
		{
			if (bUseActorTick)
				SetStateLabel("Other");
		}
		Loop;
	Other:
		SPOS A 1
		{
			if (!bUseActorTick)
				SetStateLabel("Spawn");
		}
		Loop;
	}
}

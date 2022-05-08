class DemoCavePlat : FCW_Platform
{
	Default
	{
		Radius 32;
		Height 24;
	}

	States
	{
	Spawn:
		MODL A -1;
		Stop;
	}
}

class DemoTwistingLift : FCW_Platform
{
	Default
	{
		Radius 64;
		Height 128;
	}

	bool wasMoving;

	States
	{
	Spawn:
		MODL A 1 NoDelay { wasMoving = false; }
		MODL A 1
		{
			bool isMoving = (PlatHasMoved() && PlatIsActive());
			if (isMoving == wasMoving)
				return;

			if (wasMoving = isMoving)
				StartSoundSequence('Platform', 0);
			else
				StopSoundSequence();
		}
		Wait;
	}
}

class DemoSpinningSegment1 : FCW_Platform
{
	Default
	{
		Radius 40;
		Height 136;
	}

	States
	{
	Spawn:
		MODL A -1;
		Stop;
	}
}

class DemoSpinningSegment2 : FCW_Platform
{
	Default
	{
		Radius 32;
		Height 128;
	}

	States
	{
	Spawn:
		MODL A -1;
		Stop;
	}
}

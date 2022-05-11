class DemoGenericPlat : FCW_Platform abstract
{
	States
	{
	Spawn:
		MODL A -1;
		Stop;
	}
}

class DemoPlatWithSnd : FCW_Platform abstract
{
	bool wasMoving;
	Name sndSeq;
	Property Seq: sndSeq;

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
				StartSoundSequence(sndSeq, 0);
			else
				StopSoundSequence();
		}
		Wait;
	}
}

//
//
//

class DemoCavePlat : DemoGenericPlat
{
	Default
	{
		Radius 32;
		Height 24;
	}
}

class DemoTwistingLift : DemoPlatWithSnd
{
	Default
	{
		Radius 64;
		Height 128;
		DemoPlatWithSnd.Seq 'Platform';
	}
}

class DemoSpinningSegment1 : DemoGenericPlat
{
	Default
	{
		Radius 40;
		Height 136;
	}
}

class DemoSpinningSegment2 : DemoGenericPlat
{
	Default
	{
		Radius 32;
		Height 128;
	}
}

class DemoSlidingFloor : DemoPlatWithSnd
{
	Default
	{
		Radius 32;
		Height 16;
		DemoPlatWithSnd.Seq 'Floor';
	}
}

class DemoWobblyMeatFloor : FCW_Platform
{
	Default
	{
		Radius 96;
		Height 248;
	}

	States
	{
	Spawn:
		MODL A random(40, 70); //Eyes open.
		MODL B random(3, 15);  //Eyes closed.
		Loop;
	}
}

class DemoWobblyMeatFloorNoEyes : DemoGenericPlat
{
	Default
	{
		Radius 96;
		Height 248;
	}
}

class DemoFirebluSegment : DemoGenericPlat
{
	Default
	{
		Radius 30;
		Height 16;
	}
}

class DemoFirebluSegmentTiny : DemoGenericPlat
{
	Default
	{
		Scale 0.2;
		Radius 6;
		Height 3.2;
	}
}

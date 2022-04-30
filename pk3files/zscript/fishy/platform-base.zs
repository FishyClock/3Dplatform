/******************************************************************************

 MIT License

 Copyright (c) 2022 FishyClockwork

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.

******************************************************************************/

class FCW_Platform : Actor abstract
{
	Default
	{
		//Some editor keys for Ultimate Doom Builder.
		//All editor key definitions have to be on one line
		//or UDB can't parse them correctly. (Yes, even "Arg1Enum")
		//For more info:
		//https://zdoom.org/wiki/Editor_keys
		//https://zdoom.org/wiki/Making_configurable_actors_in_DECORATE

		//$Arg0 Interpolation Point
		//$Arg0Type 14

		//$Arg1 Options
		//$Arg1Type 12
		//$Arg1Enum {1 = "Linear path"; 2 = "Use point angle / Group move: Rotate angle"; 4 = "Use point pitch / Group move: Rotate pitch"; 8 = "Use point roll / Group move: Rotate roll"; 16 = "Face movement direction"; 32 = "Don't clip against geometry and other platforms"; 64 = "Start active"; 128 = "Group move: Mirror group origin's movement";}
		//$Arg1Tooltip Anything with 'Group move' affects movement imposed by the group origin.\nIt does nothing for the group origin itself.\nThe 'group origin' is the platform that the others move with and orbit around.

		//$Arg2 Travel/Hold Time Unit
		//$Arg2Type 11
		//$Arg2Enum {0 = "Octics (default)"; 1 = "Tics"; 2 = "Seconds";}
		//$Arg2Tooltip Does nothing if being moved by group origin.\nThe 'group origin' is the platform that the others move with and orbit around.

		//$Arg3 Platform(s) To Group With
		//$Arg3Type 14

		//$Arg4 Crush Damage
		//$Arg4Tooltip The damage is applied once per 4 tics.

		+ACTLIKEBRIDGE;
		+NOGRAVITY;
		+CANPASS;
		+SOLID;
		+SHOOTABLE; //Block hitscan attacks

		//These are needed because we're shootable
		+NODAMAGE;
		+NOBLOOD;
		+DONTTHRUST;
		+NOTAUTOAIMED;
	}
}

//Ultimate Doom Builder doesn't need to read the rest
//$GZDB_SKIP

class FCW_PlatformGroup play
{
	private Array<FCW_Platform> members;
	transient uint index;
	FCW_Platform origin; //Group mover that does most of the thinking for the others. Other members are always "inactive" platforms.

	static FCW_PlatformGroup Create ()
	{
		let group = new("FCW_PlatformGroup");
		group.members.Clear();
		group.index = 0;
		group.origin = null;
		return group;
	}

	void Add (FCW_Platform plat)
	{
		plat.group = self;
		if (members.Find(plat) >= members.Size())
			members.Push(plat);
	}

	FCW_Platform GetFirst ()
	{
		index = 0;
		return GetNext();
	}

	FCW_Platform GetNext ()
	{
		//Handle invalid entries
		while (index < members.Size() && !members[index])
			members.Delete(index);

		if (index < members.Size())
			return members[index++];

		return null;
	}

	void VerifyMembers ()
	{
		//Ensure all members point to this group
		for (let plat = GetFirst(); plat; plat = GetNext())
			plat.group = self;

		//Ensure 'origin' is a member and points to this group
		if (origin)
			Add(origin);
	}

	void MergeWith (FCW_PlatformGroup otherGroup)
	{
		for (let plat = otherGroup.GetFirst(); plat; plat = otherGroup.GetNext())
			Add(plat);
	}
}

extend class FCW_Platform
{
	enum ArgValues
	{
		ARG_NODETID			= 0,
		ARG_OPTIONS			= 1,
		ARG_TIMEUNIT		= 2,
		ARG_GROUPTID		= 3,
		ARG_CRUSHDMG		= 4,

		//For "ARG_OPTIONS"
		OPTFLAG_LINEAR			= 1,
		OPTFLAG_ANGLE			= 2,
		OPTFLAG_PITCH			= 4,
		OPTFLAG_ROLL			= 8,
		OPTFLAG_FACEMOVE		= 16,
		OPTFLAG_IGNOREGEO		= 32,
		OPTFLAG_STARTACTIVE		= 64,
		OPTFLAG_MIRROR			= 128,

		//For "ARG_TIMEUNIT"
		TIMEUNIT_OCTICS		= 0,
		TIMEUNIT_TICS		= 1,
		TIMEUNIT_SECS		= 2,

		//"InterpolationPoint" args that we check
		NODEARG_TRAVELTIME	= 1,
		NODEARG_HOLDTIME	= 2,
	};

	const TOPEPSILON = 1.0;
	const ACTIVATION_AGE = 1;

	vector3 oldPos;
	double oldAngle;
	double oldPitch;
	double oldRoll;
	double spawnPitch;
	double spawnRoll;
	double time, timeFrac;
	int holdTime;
	bool bActive;
	bool bJustStepped;
	bool bPlatBlocked; //Only useful for ACS. (See utility functions below.)
	transient bool bPlatInMove; //No collision between a platform and its riders during said platform's move.
	InterpolationPoint currNode, firstNode;
	InterpolationPoint prevNode, firstPrevNode;
	Array<Actor> riders;
	FCW_PlatformGroup group;
	Actor delayedActivator;

	//Unlike PathFollower classes, our interpolations are done with
	//vector3 coordinates rather than checking InterpolationPoint positions.
	//This is done for 2 reasons:
	//1) Making it portal aware.
	//2) Can be arbitrarily set through ACS (See utility functions below).
	vector3 pCurr, pPrev, pNext, pNextNext; //Positions in the world.
	vector3 pCurrAngs, pPrevAngs, pNextAngs, pNextNextAngs; //X = angle, Y = pitch, Z = roll.

	//============================
	// BeginPlay (override)
	//============================
	override void BeginPlay ()
	{
		Super.BeginPlay();

		oldPos = pos;
		oldAngle = angle;
		oldPitch = pitch;
		oldRoll = roll;
		spawnPitch = pitch;
		spawnRoll = roll;
		time = timeFrac = 0;
		holdTime = 0;
		bActive = false;
		bJustStepped = false;
		bPlatBlocked = false;
		bPlatInMove = false;
		currNode = firstNode = null;
		prevNode = firstPrevNode = null;
		riders.Clear();
		group = null;
		delayedActivator = null;

		pCurr = pPrev = pNext = pNextNext = (0, 0, 0);
		pCurrAngs = pPrevAngs = pNextAngs = pNextNextAngs = (0, 0, 0);
	}

	//============================
	// PostBeginPlay (override)
	//============================
	override void PostBeginPlay ()
	{
		Super.PostBeginPlay();

		let it = level.CreateActorIterator(args[ARG_GROUPTID], "FCW_Platform");
		FCW_Platform plat;
		while (plat = FCW_Platform(it.Next()))
		{
			if (plat.group) //Target is in its own group?
			{
				if (!group) //We don't have a group?
					plat.group.Add(self);
				else if (plat.group != group) //Both are in different groups?
					plat.group.MergeWith(group);
				//else - nothing happens because it's the same group or plat == self
			}
			else if (group) //We're in a group but target doesn't have a group?
			{
				group.Add(plat);
			}
			else if (plat != self) //Neither are in a group
			{
				let newGroup = FCW_PlatformGroup.Create();
				newGroup.Add(self);
				newGroup.Add(plat);
			}
		}

		//Print no warnings if we're not supposed to have a interpolation point
		if (!args[ARG_NODETID])
		{
			//In case the mapper placed walking monsters on the platform
			//get something for HandleOldRiders() to monitor.
			GetNewRiders(true);
			return; 
		}

		String prefix = "\ckPlatform class '" .. GetClassName() .. "' with tid " .. tid .. ":\nat position " .. pos .. ":\n";

		it = level.CreateActorIterator(args[ARG_NODETID], "InterpolationPoint");
		firstNode = InterpolationPoint(it.Next());
		if (!firstNode)
		{
			Console.Printf(prefix .. "Can't find interpolation point with tid " .. args[ARG_NODETID] .. ".");
			return;
		}

		//Verify the path has enough nodes
		firstNode.FormChain();
		if (args[ARG_OPTIONS] & OPTFLAG_LINEAR)
		{
			if (!firstNode.next) //Linear path; need 2 nodes
			{
				Console.Printf(prefix .. "Path needs at least 2 nodes.");
				return;
			}
		}
		else //Spline path; need 4 nodes
		{
			if (!firstNode.next ||
				!firstNode.next.next ||
				!firstNode.next.next.next)
			{
				Console.Printf(prefix .. "Path needs at least 4 nodes.");
				return;
			}

			//If the first node is in a loop, we can start there.
			//Otherwise, we need to start at the second node in the path.
			firstPrevNode = firstNode.ScanForLoop();
			if (!firstPrevNode || firstPrevNode.next != firstNode)
			{
				firstPrevNode = firstNode;
				firstNode = firstNode.next;
			}
		}

		if (args[ARG_OPTIONS] & OPTFLAG_STARTACTIVE)
			Activate(self);
		else if (firstNode)			//In case the mapper placed walking monsters on the platform
			GetNewRiders(true);		//get something for HandleOldRiders() to monitor.
	}

	//============================
	// CanCollideWith (override)
	//============================
	override bool CanCollideWith(Actor other, bool passive)
	{
		let plat = FCW_Platform(other);

		//For speed's sake assume they're both in the group array without actually checking
		if (plat && ((plat.group && plat.group == group) || (args[ARG_OPTIONS] & OPTFLAG_IGNOREGEO)))
			return false;

		if (bPlatInMove && riders.Find(other) < riders.Size())
			return false;

		return true;
	}

	//============================
	// CollisionFlagChecks
	//============================
	private bool CollisionFlagChecks (Actor a, Actor b)
	{
		if (a.bThruActors || b.bThruActors)
			return false;

		if (!a.bSolid || !b.bSolid)
			return false;

		if ((a.bAllowThruBits || b.bAllowThruBits) && (a.thruBits & b.thruBits))
			return false;

		if ((a.bThruSpecies || b.bThruSpecies) && a.GetSpecies() == b.GetSpecies())
			return false;

		return true;
	}

	//============================
	// OverlapXY
	//============================
	private bool OverlapXY (Actor a, Actor b)
	{
		double blockDist = a.radius + b.radius;
		vector2 vec = level.Vec2Diff(a.pos.xy, b.pos.xy);
		return (abs(vec.x) < blockDist && abs(vec.y) < blockDist);
	}

	//============================
	// FitsAtPosition
	//============================
	private bool FitsAtPosition (Actor mo, vector3 testPos)
	{
		// CheckMove() does more checks than TestMobjLocation().
		// It takes into account floor/ceiling huggers and
		// the CANTLEAVEFLOORPIC flag.
		//
		// It's useful if there's XY position changes while
		// TestMobjLocation() is enough for Z changes only.

		bool result;
		let oldZ = mo.pos.z;
		mo.SetZ(testPos.z); //Set Z before anything else because Z also has an effect on CheckMove()'s outcome

		//Even if XY is unaltered, having any of these flags means CheckMove() should handle it anyway
		if (mo.pos.xy == testPos.xy && !mo.bFloorHugger && !mo.bCeilingHugger && !mo.bCantLeaveFloorPic)
		{
			result = mo.TestMobjLocation();
		}
		else
		{
			FCheckPosition tm;
			result = (mo.CheckMove(testPos.xy, 0, tm) &&
				testPos.z >= tm.floorZ &&				//This is something that TestMobjLocation() checks
				testPos.z + mo.height <= tm.ceilingZ);	//and that CheckMove() does not account for.
		}

		mo.SetZ(oldZ);
		return result;
	}

	//============================
	// CrushObstacle
	//============================
	private void CrushObstacle (Actor victim)
	{
		int crushDamage = args[ARG_CRUSHDMG];
		if (crushDamage <= 0 || (level.mapTime & 3)) //Only crush every 4th tic to allow victim's pain sound to be heard
			return;

		int doneDamage = victim.DamageMobj(null, null, crushDamage, 'Crush');
		victim.TraceBleed(doneDamage > 0 ? doneDamage : crushDamage, self);
	}

	//============================
	// PushObstacle
	//============================
	private void PushObstacle (Actor pushed, vector3 pushForce)
	{
		//Don't bother if it's close to nothing
		if (pushForce.x ~== 0) pushForce.x = 0;
		if (pushForce.y ~== 0) pushForce.y = 0;
		if (pushForce.z ~== 0) pushForce.z = 0;

		if (pushForce.z && !OverlapXY(self, pushed)) //Out of range?
			pushForce.z = 0;

		if (pushForce == (0, 0, 0))
			return;

		if (pos.xy != pushed.pos.xy && pushForce.xy != (0, 0))
		{
			double delta = DeltaAngle(VectorAngle(pushForce.x, pushForce.y), AngleTo(pushed));
			if (delta > 90 || delta < -90)
				pushForce.xy = RotateVector(pushForce.xy, delta); //Push away from platform's center
		}
		pushed.vel += pushForce;

		if (args[ARG_CRUSHDMG] <= 0)
			return;

		if (!FitsAtPosition(pushed, level.Vec3Offset(pushed.pos, pushForce)))
			CrushObstacle(pushed);
	}

	//============================
	// SetTimeFraction
	//============================
	private void SetTimeFraction (int newTime)
	{
		switch (args[ARG_TIMEUNIT])
		{
			default:
			case TIMEUNIT_OCTICS:
				timeFrac = 8.0 / (max(1, newTime) * TICRATE); //Interpret 'newTime' as octics
				break;
			case TIMEUNIT_TICS:
				timeFrac = 1.0 / max(1, newTime); //Interpret 'newTime' as tics
				break;
			case TIMEUNIT_SECS:
				timeFrac = 1.0 / (max(1, newTime) * TICRATE); //Interpret 'newTime' as seconds
				break;
		}
	}

	//============================
	// SetHoldTime
	//============================
	private void SetHoldTime (int newTime)
	{
		if (newTime <= 0)
			return;

		switch (args[ARG_TIMEUNIT])
		{
			default:
			case TIMEUNIT_OCTICS:
				holdTime = level.mapTime + newTime * TICRATE / 8; //Interpret 'newTime' as octics
				break;
			case TIMEUNIT_TICS:
				holdTime = level.mapTime + newTime; //Interpret 'newTime' as tics
				break;
			case TIMEUNIT_SECS:
				holdTime = level.mapTime + newTime * TICRATE; //Interpret 'newTime' as seconds
				break;
		}
	}

	//============================
	// SetInterpolationCoordinates
	//============================
	private void SetInterpolationCoordinates ()
	{
		if (prevNode)
		{
			pPrev = pos + Vec3To(prevNode); //Make it portal aware
			pPrevAngs = (
				Normalize180(prevNode.angle),
				Normalize180(prevNode.pitch),
				Normalize180(prevNode.roll));
		}
		if (currNode)
		{
			pCurr = pos + Vec3To(currNode); //Ditto
			if (!prevNode)
				pCurrAngs = (
				Normalize180(currNode.angle),
				Normalize180(currNode.pitch),
				Normalize180(currNode.roll));
			else
				pCurrAngs = pPrevAngs + (
				DeltaAngle(pPrevAngs.x, currNode.angle),
				DeltaAngle(pPrevAngs.y, currNode.pitch),
				DeltaAngle(pPrevAngs.z, currNode.roll));

			if (currNode.next)
			{
				pNext = pos + Vec3To(currNode.next); //Ditto
				pNextAngs = pCurrAngs + (
				DeltaAngle(pCurrAngs.x, currNode.next.angle),
				DeltaAngle(pCurrAngs.y, currNode.next.pitch),
				DeltaAngle(pCurrAngs.z, currNode.next.roll));

				if (currNode.next.next)
				{
					pNextNext = pos + Vec3To(currNode.next.next); //Ditto
					pNextNextAngs = pNextAngs + (
					DeltaAngle(pNextAngs.x, currNode.next.next.angle),
					DeltaAngle(pNextAngs.y, currNode.next.next.pitch),
					DeltaAngle(pNextAngs.z, currNode.next.next.roll));
				}
			}
		}
	}

	//============================
	// IsCarriable
	//============================
	private bool IsCarriable (Actor mo)
	{
		//Due to how the engine handles actor-to-actor interactions
		//we can only carry things with the CANPASS or the
		//SPECIAL flag. Anything else will just fall through.
		//Even when we have ACTLIKEBRIDGE.
		if (!mo.bCanPass && !mo.bSpecial)
			return false;

		//Don't bother with floor/ceiling huggers since
		//they're not meant to be in mid-air.
		if (mo.bFloorHugger || mo.bCeilingHugger)
			return false;

		//Apparently CANTLEAVEFLOORPIC is similiar to FLOORHUGGER?
		//Because any move that results in its Z being different
		//from its 'floorZ' is invalid according to CheckMove().
		if (mo.bCantLeaveFloorPic)
			return false;

		return true;
	}

	//============================
	// GetNewRiders
	//============================
	private bool GetNewRiders (bool ignoreObs)
	{
		//In addition to fetching riders, this is where corpses get crushed, too. Items won't get destroyed.
		//Returns false if an actor is completely stuck inside platform unless 'ignoreObs' is true.

		double top = pos.z + height;
		Array<Actor> miscActors; //The actors on top of the riders (We'll move those, too)
		Array<Actor> onTopOfMe;
		Array<FCW_Platform> otherPlats;

		//Call Grind() after we're done iterating because destroying
		//actors during iteration can mess up the iterator.
		Array<Actor> corpses;

		//Three things to do here when iterating:
		//1) Gather eligible riders.
		//2) Damage any non-platform actors that are stuck inside platform (and can't be placed on top of platform)
		//3) If said actors are corpses, "grind" them instead.

		//NOTE: Only one live actor can get damaged per tic and makes this function return false.
		//While all detected corpses will be grinded in one go and won't stop the gathering process.
		let it = BlockThingsIterator.Create(self);
		while (it.Next())
		{
			let mo = it.thing;
			if (mo == self)
				continue;

			bool canCarry = (IsCarriable(mo) && !(mo is "FCW_Platform")); //Platforms shouldn't carry other platforms.
			bool oldRider = (riders.Find(mo) < riders.Size());
			if (mo is "FCW_Platform")
				otherPlats.Push(FCW_Platform(mo));

			//Check XY overlap
			double blockDist = radius + mo.radius;
			if (abs(it.position.x - mo.pos.x) < blockDist && abs(it.position.y - mo.pos.y) < blockDist)
			{
				//'ignoreObs' makes anything above our 'top' legit
				if (mo.pos.z >= top && (ignoreObs || mo.pos.z <= top + TOPEPSILON)) //On top of us?
				{
					if (canCarry && !oldRider)
						onTopOfMe.Push(mo);
					continue;
				}

				if (mo.pos.z + mo.height > pos.z && top > mo.pos.z) //Overlaps Z?
				{
					if (mo.bCorpse && !mo.bDontGib && mo.tics == -1) //Let dying actors finish their death sequence
					{
						if (!ignoreObs)
							corpses.Push(mo);
					}
					else if (CollisionFlagChecks(self, mo) && self.CanCollideWith(mo, false) && mo.CanCollideWith(self, true))
					{
						//Try to correct 'mo' Z so it can ride us, too.
						//But only if its 'maxStepHeight' allows it.
						bool blocked = true;
						if (canCarry && top - mo.pos.z <= mo.maxStepHeight)
						{
							blocked = !FitsAtPosition(mo, (mo.pos.xy, top));
							if (!blocked)
								mo.SetZ(top);
						}
						if (blocked)
						{
							if (!(mo is "FCW_Platform"))
							{
								if (!ignoreObs)
									CrushObstacle(mo);
							}
							if (!ignoreObs)
							{
								for (int i = 0; i < corpses.Size(); ++i)
									corpses[i].Grind(false);
								return false; //Try again in the next tic
							}
							else continue;
						}
						if (!oldRider)
							onTopOfMe.Push(mo);
					}
					else if (mo is "Inventory" && mo.bSpecial) //Item that can be picked up?
					{
						//Try to correct 'mo' Z so it can ride us, too.
						//But only if its 'maxStepHeight' allows it.
						if (canCarry && top - mo.pos.z <= mo.maxStepHeight &&
							FitsAtPosition(mo, (mo.pos.xy, top)))
						{
							mo.SetZ(top);
							if (!oldRider)
								onTopOfMe.Push(mo);
						}
					}
					continue;
				}
			}

			if (canCarry && !oldRider)
				miscActors.Push(mo); //We'll compare this later against the riders
		}

		for (int i = 0; i < corpses.Size(); ++i)
			corpses[i].Grind(false);

		//Do NOT take other platforms' riders unless our top is higher
		for (int iPlat = 0; iPlat < otherPlats.Size(); ++iPlat)
		{
			let plat = otherPlats[iPlat];
			bool myTopIsHigher = (top > plat.pos.z + plat.height);

			for (int i = 0; i < onTopOfMe.Size(); ++i)
			{
				let index = plat.riders.Find(onTopOfMe[i]);
				if (index < plat.riders.Size())
				{
					if (myTopIsHigher)
						plat.riders.Delete(index); //Steal it!
					else
						onTopOfMe.Delete(i--);
				}
			}
			for (int i = 0; i < miscActors.Size(); ++i)
			{
				if (plat.riders.Find(miscActors[i]) < plat.riders.Size())
					miscActors.Delete(i--);
			}
		}
		riders.Append(onTopOfMe);

		//Now figure out which of the misc actors are on top of/stuck inside
		//established riders.
		for (int i = 0; i < riders.Size(); ++i)
		{
			let mo = riders[i];
			double moTop = mo.pos.z + mo.height + TOPEPSILON;

			for (int iOther = 0; iOther < miscActors.Size(); ++iOther)
			{
				let otherMo = miscActors[iOther];

				if (moTop > otherMo.pos.z && otherMo.pos.z + otherMo.height > mo.pos.z && //Is 'otherMo' on top of or stuck inside 'mo'?
					OverlapXY(mo, otherMo)) //Within XY range?
				{
					miscActors.Delete(iOther--); //Don't compare this one against other riders anymore
					riders.Push(otherMo);
				}
			}
		}
		return true;
	}

	//============================
	// MoveRiders
	//============================
	private bool MoveRiders (bool teleMove)
	{
		//Returns false if a blocked rider would block the platform's movement unless 'teleMove' is true

		if (!riders.Size())
			return true; //No riders? Nothing to do

		//The goal is to move all riders as if they were one entity.
		//The only things that should block any of them are
		//non-riders and geometry.
		//The exception is if a rider can't fit at its new position
		//in which case it will be "solid" for the others.
		//
		//To accomplish this each of them will temporarily
		//be removed from the blockmap.

		int addToBmap = 0, removeFromBmap = 1;

		for (int i = 0; i < riders.Size(); ++i)
			riders[i].A_ChangeLinkFlags(removeFromBmap);

		//Move our riders (platform rotation is taken into account)
		double top = pos.z + height;
		double delta = DeltaAngle(oldAngle, angle);
		double c = cos(delta), s = sin(delta);
		vector2 piAndRoOffset = (0, 0);
		if (!teleMove)
		{
			double piDelta = DeltaAngle(oldPitch, pitch)*2;
			double roDelta = DeltaAngle(oldRoll, roll)*2;
			piAndRoOffset = (cos(angle)*piDelta, sin(angle)*piDelta) + //Front/back
				(cos(angle-90)*roDelta, sin(angle-90)*roDelta); //Right/left
		}

		Array<double> preMovePos; //Sadly we can't have a vector2/3 dyn array
		for (int i = 0; i < riders.Size(); ++i)
		{
			let mo = riders[i];
			let moOldPos = mo.pos;

			vector3 offset = level.Vec3Diff(oldPos, moOldPos);
			offset.xy = (offset.x*c - offset.y*s, offset.x*s + offset.y*c); //Rotate it
			offset.xy += piAndRoOffset;
			vector3 moNewPos = level.Vec3Offset(pos, offset);

			//Handle z discrepancy
			if (moNewPos.z < top && moNewPos.z + mo.height >= top)
				moNewPos.z = top;

			bool moved;
			if (teleMove)
			{
				moved = FitsAtPosition(mo, moNewPos);
				if (moved)
					mo.SetOrigin(moNewPos, false);
			}
			else
			{
				int maxSteps = 1;
				vector3 stepMove = level.Vec3Diff(moOldPos, moNewPos);

				//If the move is equal or larger than the rider's radius
				//then it has to be split up into smaller steps.
				//This is needed for proper collision and to ensure
				//lines with specials aren't skipped.
				double maxMove = max(1, mo.radius - 1);
				double moveSpeed = max(abs(stepMove.x), abs(stepMove.y));
				if (moveSpeed > maxMove)
				{
					maxSteps = int(1 + moveSpeed / maxMove);
					stepMove /= maxSteps;
				}

				//NODROPOFF overrides TryMove()'s second argument,
				//but the rider should be treated like a flying object.
				let moOldNoDropoff = mo.bNoDropoff;
				mo.bNoDropoff = false;
				moved = true;
				for (int step = 0; step < maxSteps; ++step)
				{
					let moOldAngle = mo.angle;
					let moOldZ = mo.pos.z;
					mo.AddZ(stepMove.z);
					vector2 tryPos = mo.pos.xy + stepMove.xy;
					if (!mo.TryMove(tryPos, 1))
					{
						mo.SetZ(moOldZ);
						moved = false;
						break;
					}

					//Take into account riders getting Thing_Remove()'d
					//when they activate lines.
					if (!mo || mo.bDestroyed)
						break;

					if (tryPos != mo.pos.xy && step < maxSteps-1)
					{
						//If 'mo' has passed through a portal then
						//adjust 'stepMove' if its angle changed.
						double angDiff = DeltaAngle(moOldAngle, mo.angle);
						if (angDiff)
							stepMove.xy = RotateVector(stepMove.xy, angDiff);
					}
				}

				//Take into account riders getting Thing_Remove()'d
				//when they activate lines.
				if (!mo || mo.bDestroyed)
				{
					riders.Delete(i--);
					continue;
				}
				mo.bNoDropoff = moOldNoDropoff;
			}

			if (moved)
			{
				//Only remember the old position if 'mo' was moved.
				//(Else we delete the 'riders' entry containing 'mo', see below.)
				preMovePos.Push(moOldPos.x);
				preMovePos.Push(moOldPos.y);
				preMovePos.Push(moOldPos.z);
			}
			else
			{
				if (mo.pos != moOldPos)
					mo.SetOrigin(moOldPos, true);

				//This rider will be 'solid' for the others
				mo.A_ChangeLinkFlags(addToBmap);
				riders.Delete(i--);

				//See if it would block the platform
				double moTop = mo.pos.z + mo.height;
				bool blocked = ( !teleMove && CollisionFlagChecks(mo, self) &&
					moTop > self.pos.z && top > mo.pos.z && //Overlaps Z?
					OverlapXY(mo, self) && //Within XY range?
					mo.CanCollideWith(self, false) && self.CanCollideWith(mo, true) );

				//See if the ones we moved already will collide with this one
				//and if yes, move them back to their old positions.
				//(If the platform's "blocked" then move everyone back unconditionally.)
				for (int iOther = 0; iOther <= i; ++iOther)
				{
					let otherMo = riders[iOther];
					if ( !blocked && ( !CollisionFlagChecks(otherMo, mo) ||
						moTop <= otherMo.pos.z || otherMo.pos.z + otherMo.height <= mo.pos.z || //No Z overlap?
						!OverlapXY(otherMo, mo) || //Out of XY range?
						!otherMo.CanCollideWith(mo, false) || !mo.CanCollideWith(otherMo, true) ) )
					{
						continue;
					}

					//Put 'otherMo' back at its old position
					vector3 otherOldPos = (preMovePos[iOther*3], preMovePos[iOther*3 + 1], preMovePos[iOther*3 + 2]);
					otherMo.SetOrigin(otherOldPos, true);

					otherMo.A_ChangeLinkFlags(addToBmap);
					preMovePos.Delete(iOther*3, 3);
					riders.Delete(iOther--);
					i--;
				}

				if (blocked)
				{
					for (i = 0; i < riders.Size(); ++i)
						riders[i].A_ChangeLinkFlags(addToBmap); //Handle those that didn't get the chance to move
					PushObstacle(mo, level.Vec3Diff(oldPos, pos));
					return false;
				}
			}
		}

		//Anyone left in the 'riders' array has moved successfully.
		//Change their angles.
		for (int i = 0; i < riders.Size(); ++i)
		{
			let mo = riders[i];
			mo.A_ChangeLinkFlags(addToBmap);
			if (delta)
				mo.angle = Normalize180(mo.angle + delta);
		}

		return true;
	}

	//============================
	// HandleOldRiders
	//============================
	private void HandleOldRiders ()
	{
		// Tracks established riders and doesn't forget them even if
		// they're above our 'top' (with no 3D floors in between).
		// Such actors are mostly jumpy players and custom AI.
		//
		// Also keep non-flying monsters away from platform's edge.
		// Because the AI's native handling of trying not to
		// fall off of other actors just isn't good enough.
		//
		// For example, if the platform moves and rotates
		// at same time and a walker is right at the edge,
		// it sometimes falls off.

		double top = pos.z + height;
		for (int i = 0; i < riders.Size(); ++i)
		{
			let mo = riders[i];
			if (!mo || mo.bDestroyed || //Got Thing_Remove()'d?
				mo.bNoBlockmap || !IsCarriable(mo))
			{
				riders.Delete(i--);
				continue;
			}

			//'floorZ' can be the top of a 3D floor that's right below an actor.
			//No 3D floors means 'floorZ' is the current sector's floor height.
			//(In other words 'floorZ' is not another actor's top that's below.)

			//Is 'mo' below our 'top'? Or is there a 3D floor above our 'top' that's also below 'mo'?
			if (mo.pos.z < top - TOPEPSILON || mo.floorZ > top + TOPEPSILON)
			{
				riders.Delete(i--);
				continue;
			}

			if (!OverlapXY(self, mo)) //Is out of XY range?
			{
				riders.Delete(i--);
				continue;
			}

			//See if we should keep it away from the edge
			if (!mo.bIsMonster || mo.bNoGravity || mo.bFloat || !mo.speed) //Is not a walking monster?
				continue;

			if (mo.bDropoff || mo.bJumpDown) //Is supposed to fall off of tall drops or jump down?
				continue;

			if (mo.tics != 1 && mo.tics != 0)
				continue; //Don't bother if it's not about to change states (and potentially call A_Chase()/A_Wander())

			if (mo.pos.z > top + TOPEPSILON)
				continue; //Not exactly on top of us

			if (mo.pos.z - mo.floorZ <= mo.maxDropoffHeight)
				continue; //Monster is close to the ground (which includes 3D floors) so let it walk off

			if (Distance2D(mo) < radius - mo.speed)
				continue; //Not close to platform's edge

			// Make your bog-standard idTech1 AI
			// that uses A_Chase() or A_Wander()
			// walk towards the platform's center.
			//
			// NOTE: This isn't fool proof if there
			// are multiple riders moving on the
			// same platform at the same time.
			//
			// Yes, this is a hack.

			mo.moveDir = int(mo.AngleTo(self) / 45) & 7;
			if (mo.moveCount < 1)
				mo.moveCount = 1;
		}
	}

	//============================
	// PlatLerp
	//============================
	private double PlatLerp (double p1, double p2)
	{
		return (p1 ~== p2) ? p1 : (p1 + time * (p2 - p1));
	}

	//============================
	// PlatSplerp
	//============================
	private double PlatSplerp (double p1, double p2, double p3, double p4)
	{
		if (p2 ~== p3)
			return p2;

		// This was copy-pasted from PathFollower's Splerp() function
		//
		// Interpolate between p2 and p3 along a Catmull-Rom spline
		// http://research.microsoft.com/~hollasch/cgindex/curves/catmull-rom.html
		//
		// NOTE: the above link doesn't seem to work so here's an alternative. -FishyClockwork
		// https://en.wikipedia.org/wiki/Cubic_Hermite_spline#Catmull%E2%80%93Rom_spline
		double t = time;
		double res = 2*p2;
		res += (p3 - p1) * time;
		t *= time;
		res += (2*p1 - 5*p2 + 4*p3 - p4) * t;
		t *= time;
		res += (3*p2 - 3*p3 + p4 - p1) * t;
		return 0.5 * res;
	}

	//============================
	// PlatTakeOneStep
	//============================
	private bool PlatTakeOneStep (vector3 newPos)
	{
		SetZ(newPos.z);
		bool moved = TryMove(newPos.xy, 1);

		if (!moved && blockingMobj && !(blockingMobj is "FCW_Platform"))
		{
			let mo = blockingMobj;
			let moOldZ = mo.pos.z;
			let moNewZ = newPos.z + self.height;

			//If we could carry it, try to set the obstacle on top of us
			//if its 'maxStepHeight' allows it.
			if (moNewZ > moOldZ && moNewZ - moOldZ <= mo.maxStepHeight &&
				IsCarriable(mo) && FitsAtPosition(mo, (mo.pos.xy, moNewZ)))
			{
				mo.SetZ(moNewZ);
				moved = TryMove(newPos.xy, 1); //Try one more time
				if (!moved)
				{
					mo.SetZ(moOldZ);
					blockingMobj = mo; //Needed for obstacle pushing; TryMove() might have nulled it
				}
			}

			if (!moved) //Blocked by actor that isn't a platform?
			{
				SetZ(oldPos.z);
				return false;
			}
		}

		if (!moved) //Blocked by geometry or another platform?
		{
			if (args[ARG_OPTIONS] & OPTFLAG_IGNOREGEO)
			{
				SetOrigin(level.Vec3Offset(pos, newPos - pos), true);
			}
			else
			{
				SetZ(oldPos.z);
				return false;
			}
		}

		return true;
	}

	//============================
	// PlatMove
	//============================
	private bool PlatMove (vector3 newPos, double newAngle, double newPitch, double newRoll, bool teleMove)
	{
		if (pos == newPos && angle == newAngle && pitch == newPitch && roll == newRoll)
			return true;

		if (!GetNewRiders(teleMove))
			return false;

		if (teleMove || pos == newPos)
		{
			oldPos = pos;
			oldAngle = angle;
			oldPitch = pitch;
			oldRoll = roll;

			if (pos != newPos)
				SetOrigin(newPos, !teleMove);
			angle = newAngle;
			pitch = newPitch;
			roll = newRoll;

			if (!MoveRiders(teleMove))
			{
				angle = oldAngle;
				pitch = oldPitch;
				roll = oldRoll;
				return false;
			}
			return true;
		}

		int maxSteps = 1;
		vector3 stepMove = level.Vec3Diff(pos, newPos);
		vector3 pushForce = stepMove;

		//If the move is equal or larger than our radius
		//then it has to be split up into smaller steps.
		//This is needed for proper collision.
		double maxMove = max(1, radius - 1);
		double moveSpeed = max(abs(stepMove.x), abs(stepMove.y));
		if (moveSpeed > maxMove)
		{
			maxSteps = int(1 + moveSpeed / maxMove);
			stepMove /= maxSteps;
		}

		for (int step = 0; step < maxSteps; ++step)
		{
			oldPos = pos;
			oldAngle = angle;
			oldPitch = pitch;
			oldRoll = roll;

			newPos = pos + stepMove;
			bPlatInMove = true; //Temporarily don't clip against riders
			bool stepped = PlatTakeOneStep(newPos);
			bPlatInMove = false;
			if (!stepped)
			{
				if (blockingMobj && !(blockingMobj is "FCW_Platform"))
					PushObstacle(blockingMobj, pushForce);
				return false;
			}

			if (newPos.xy != pos.xy && step < maxSteps-1)
			{
				//If we have passed through a portal then
				//adjust 'stepMove' if our angle changed.
				double angDiff = DeltaAngle(oldAngle, angle);
				if (angDiff)
					stepMove.xy = RotateVector(stepMove.xy, angDiff);
			}

			if (step == 0)
			{
				angle = newAngle;
				pitch = newPitch;
				roll = newRoll;
			}

			if (!MoveRiders(false))
			{
				SetOrigin(oldPos, true);
				angle = oldAngle;
				pitch = oldPitch;
				roll = oldRoll;
				return false;
			}
		}

		return true;
	}

	//============================
	// Interpolate
	//============================
	private bool Interpolate ()
	{
		//A heavily modified version of the
		//original function from PathFollower.

		Vector3 dpos = (0, 0, 0);
		if ((args[ARG_OPTIONS] & OPTFLAG_FACEMOVE) && time > 0)
			dpos = pos;

		vector3 newPos;
		double newAngle = angle;
		double newPitch = pitch;
		double newRoll = roll;

		if (args[ARG_OPTIONS] & OPTFLAG_LINEAR)
		{
			newPos.x = PlatLerp(pCurr.x, pNext.x);
			newPos.y = PlatLerp(pCurr.y, pNext.y);
			newPos.z = PlatLerp(pCurr.z, pNext.z);
		}
		else //Spline
		{
			newPos.x = PlatSplerp(pPrev.x, pCurr.x, pNext.x, pNextNext.x);
			newPos.y = PlatSplerp(pPrev.y, pCurr.y, pNext.y, pNextNext.y);
			newPos.z = PlatSplerp(pPrev.z, pCurr.z, pNext.z, pNextNext.z);
		}

		if (args[ARG_OPTIONS] & (OPTFLAG_ANGLE | OPTFLAG_PITCH | OPTFLAG_ROLL))
		{
			if (args[ARG_OPTIONS] & OPTFLAG_FACEMOVE)
			{
				if (args[ARG_OPTIONS] & OPTFLAG_LINEAR)
				{
					dpos = pNext - pCurr;
				}
				else if (time > 0) //Spline
				{
					dpos = newPos - dpos;
				}
				else if (args[ARG_OPTIONS] & (OPTFLAG_ANGLE | OPTFLAG_PITCH))
				{	//Spline but with time <= 0
					dpos = newPos;
					time = timeFrac;
					newPos.x = PlatSplerp(pPrev.x, pCurr.x, pNext.x, pNextNext.x);
					newPos.y = PlatSplerp(pPrev.y, pCurr.y, pNext.y, pNextNext.y);
					newPos.z = PlatSplerp(pPrev.z, pCurr.z, pNext.z, pNextNext.z);
					time = 0;
					dpos = newPos - dpos;
					newPos -= dpos;
				}

				//Adjust angle
				if (args[ARG_OPTIONS] & OPTFLAG_ANGLE)
					newAngle = VectorAngle(dpos.x, dpos.y);

				//Adjust pitch
				if (args[ARG_OPTIONS] & OPTFLAG_PITCH)
				{
					double dist = dpos.xy.Length();
					newPitch = dist ? VectorAngle(dist, -dpos.z) : 0;
				}
				//Adjust roll
				if (args[ARG_OPTIONS] & OPTFLAG_ROLL)
					newRoll = 0;
			}
			else
			{
				if (args[ARG_OPTIONS] & OPTFLAG_LINEAR)
				{
					//Interpolate angle
					if (args[ARG_OPTIONS] & OPTFLAG_ANGLE)
						newAngle = PlatLerp(pCurrAngs.x, pNextAngs.x);

					//Interpolate pitch
					if (args[ARG_OPTIONS] & OPTFLAG_PITCH)
						newPitch = PlatLerp(pCurrAngs.y, pNextAngs.y);

					//Interpolate roll
					if (args[ARG_OPTIONS] & OPTFLAG_ROLL)
						newRoll = PlatLerp(pCurrAngs.z, pNextAngs.z);
				}
				else //Spline
				{
					//Interpolate angle
					if (args[ARG_OPTIONS] & OPTFLAG_ANGLE)
						newAngle = PlatSplerp(pPrevAngs.x, pCurrAngs.x, pNextAngs.x, pNextNextAngs.x);

					//Interpolate pitch
					if (args[ARG_OPTIONS] & OPTFLAG_PITCH)
						newPitch = PlatSplerp(pPrevAngs.y, pCurrAngs.y, pNextAngs.y, pNextNextAngs.y);

					//Interpolate roll
					if (args[ARG_OPTIONS] & OPTFLAG_ROLL)
						newRoll = PlatSplerp(pPrevAngs.z, pCurrAngs.z, pNextAngs.z, pNextNextAngs.z);
				}
			}
		}

		let oldPGroup = curSector.portalGroup;
		if (!PlatMove(newPos, newAngle, newPitch, newRoll, false))
			return false;

		if (curSector.portalGroup != oldPGroup && pos != newPos) //Crossed a portal?
		{
			//Offset the coordinates
			vector3 offset = pos - newPos;
			pPrev += offset;
			pCurr += offset;
			pNext += offset;
			pNextNext += offset;
		}

		//If one of our attached platforms is blocked, pretend
		//we're blocked too. (Our move won't be cancelled.)
		return MoveGroup(false);
	}

	//============================
	// MoveGroup
	//============================
	private bool MoveGroup (bool teleMove)
	{
		if (!group)
			return true;

		double delta = DeltaAngle(spawnAngle, angle);
		double piDelta = DeltaAngle(spawnPitch, pitch);
		double roDelta = DeltaAngle(spawnRoll, roll);

		double cFirst = 0, sFirst = 0;
		double cY, sY;
		double cP, sP;
		double cR, sR;
		double cLast, sLast;

		for (let plat = group.GetFirst(); plat; plat = group.GetNext())
		{
			if (plat == self)
				continue;

			bool changeAng = (plat.args[ARG_OPTIONS] & OPTFLAG_ANGLE);
			bool changePi = (plat.args[ARG_OPTIONS] & OPTFLAG_PITCH);
			bool changeRo = (plat.args[ARG_OPTIONS] & OPTFLAG_ROLL);

			vector3 newPos;
			double newAngle = plat.angle;
			double newPitch = plat.pitch;
			double newRoll = plat.roll;

			if (plat.args[ARG_OPTIONS] & OPTFLAG_MIRROR)
			{
				//The way we mirror movement is by getting the offset going
				//from the origin's current position to its 'spawnPoint'
				//and using that to get a offsetted position from
				//the attached platform's 'spawnPoint'.
				//So we pretty much always go in the opposite direction
				//using our 'spawnPoint' as a reference point.
				vector3 offset = level.Vec3Diff(pos, spawnPoint);
				newPos = level.Vec3Offset(plat.spawnPoint, offset);

				if (changeAng)
					newAngle = plat.spawnAngle - delta;
				if (changePi)
					newPitch = plat.spawnPitch - piDelta;
				if (changeRo)
					newRoll = plat.spawnRoll - roDelta;
			}
			else //Non-mirror movement. Orbiting happens here.
			{
				if (cFirst == sFirst) //Not called cos() and sin() yet?
				{
					cFirst = cos(-spawnAngle); sFirst = sin(-spawnAngle);
					cY = cos(delta);   sY = sin(delta);
					cP = cos(piDelta); sP = sin(piDelta);
					cR = cos(roDelta); sR = sin(roDelta);
					cLast = cos(spawnAngle);   sLast = sin(spawnAngle);
				}
				vector3 offset = level.Vec3Diff(spawnPoint, plat.spawnPoint);

				//Rotate the offset. The order here matters.
				offset.xy = (offset.x*cFirst - offset.y*sFirst, offset.x*sFirst + offset.y*cFirst); //Rotate to 0 angle degrees of origin
				offset = (offset.x, offset.y*cR - offset.z*sR, offset.y*sR + offset.z*cR);  //X axis (roll)
				offset = (offset.x*cP + offset.z*sP, offset.y, -offset.x*sP + offset.z*cP); //Y axis (pitch)
				offset = (offset.x*cY - offset.y*sY, offset.x*sY + offset.y*cY, offset.z);  //Z axis (yaw/angle)
				offset.xy = (offset.x*cLast - offset.y*sLast, offset.x*sLast + offset.y*cLast); //Rotate back to origin's 'spawnAngle'

				newPos = level.Vec3Offset(pos, offset);

				if (changeAng)
					newAngle = plat.spawnAngle + delta;

				if (changePi || changeRo)
				{
					double diff = DeltaAngle(spawnAngle, plat.spawnAngle);
					double c = cos(diff), s = sin(diff);
					if (changePi)
						newPitch = plat.spawnPitch + piDelta*c - roDelta*s;
					if (changeRo)
						newRoll = plat.spawnRoll + piDelta*s + roDelta*c;
				}
			}

			if (!plat.PlatMove(newPos, newAngle, newPitch, newRoll, teleMove))
				return false;
		}
		return true;
	}

	//============================
	// CallNodeSpecials
	//============================
	private void CallNodeSpecials ()
	{
		let it = level.CreateActorIterator(currNode.tid, "InterpolationSpecial");
		Actor spec;

		//Precaution against Thing_Remove() shenanigans.
		//If a special holder gets removed/destroyed
		//during iteration then the iterator gets
		//messed up. Gather all specials before
		//calling them.
		Array<int> specList;
		while ((spec = it.Next()) && spec.special)
		{
			specList.Push(spec.special);
			for (int i = 0; i < 5; ++i)
				specList.Push(spec.args[i]);
		}

		for (int i = 0; i < specList.Size(); i += 6)
			level.ExecuteSpecial(specList[i], null, null, false, specList[i+1], specList[i+2], specList[i+3], specList[i+4], specList[i+5]);
	}

	//============================
	// Deactivate (override)
	//============================
	override void Deactivate (Actor activator)
	{
		bActive = false;
	}

	//============================
	// Activate (override)
	//============================
	override void Activate (Actor activator)
	{
		if (!bActive || (group && group.origin != self))
		{
			//Do not activate too early because it's possible
			//there are platforms that have yet to attach
			//themselves to our group which means not all of
			//them would move with the origin (self) in the
			//first tic after activation.
			//This problem is apparent if the first interpolation
			//point has a defined hold time.
			if (GetAge() < ACTIVATION_AGE)
			{
				delayedActivator = activator ? activator : Actor(self);
				return;
			}
			currNode = firstNode;
			prevNode = firstPrevNode;

			if (currNode)
			{
				CallNodeSpecials();
				if (bDestroyed || !currNode || currNode.bDestroyed)
					return; //Abort if we or the node got Thing_Remove()'d

				bActive = true;
				if (group)
					group.origin = self;

				double newAngle = (args[ARG_OPTIONS] & OPTFLAG_ANGLE) ? currNode.angle : angle;
				double newPitch = (args[ARG_OPTIONS] & OPTFLAG_PITCH) ? currNode.pitch : pitch;
				double newRoll = (args[ARG_OPTIONS] & OPTFLAG_ROLL) ? currNode.roll : roll;
				PlatMove(currNode.pos, newAngle, newPitch, newRoll, true);
				MoveGroup(true);
				bJustStepped = true;
				SetInterpolationCoordinates();

				SetTimeFraction(currNode.args[NODEARG_TRAVELTIME]);
				time = 0;
				holdTime = 0;
			}
		}
	}

	//============================
	// Tick (override)
	//============================
	override void Tick ()
	{
		if (IsFrozen())
			return;

		if (delayedActivator && GetAge() >= ACTIVATION_AGE)
		{
			Activate(delayedActivator);
			delayedActivator = null;
		}

		if (group && !(level.mapTime & 63))
		{
			if (group.GetFirst() == self)
				group.VerifyMembers();
		}

		HandleOldRiders();

		while (bActive && (!group || group.origin == self))
		{
			bPlatBlocked = false;
			oldPos = pos;
			oldAngle = angle;
			oldPitch = pitch;
			oldRoll = roll;

			if (bJustStepped)
			{
				bJustStepped = false;
				if (currNode)
					SetHoldTime(currNode.args[NODEARG_HOLDTIME]);
			}

			if (holdTime > level.mapTime)
				break;

			if (!Interpolate())
			{
				bPlatBlocked = true;
				break;
			}

			time += timeFrac;
			if (time > 1.0)
			{
				time -= 1.0;
				bJustStepped = true;
				prevNode = currNode;
				if (currNode)
					currNode = currNode.next;

				if (currNode)
				{
					CallNodeSpecials();
					if (bDestroyed)
						return; //Abort if we got Thing_Remove()'d

					if (!currNode || currNode.bDestroyed)
					{
						Deactivate(self);
						break; //Our node got Thing_Remove()'d
					}
					SetInterpolationCoordinates();
					SetTimeFraction(currNode.args[NODEARG_TRAVELTIME]);
				}

				if (!currNode || !currNode.next)
					Deactivate(self);
				else if (!(args[ARG_OPTIONS] & OPTFLAG_LINEAR) && !currNode.next.next)
					Deactivate(self);
			}
			break;
		}

		if (!CheckNoDelay())
			return; //Freed itself (ie got destroyed)

		//Advance states
		if (tics != -1 && --tics <= 0)
			SetState(curState.nextState);
	}

	//============================
	// CommonACSSetup
	//============================
	private void CommonACSSetup (int newTime)
	{
		if (group)
			group.origin = self;
		currNode = null; //Deactivate when done moving
		prevNode = null;
		time = 0;
		holdTime = 0;
		SetTimeFraction(newTime);
		bActive = true;
		pPrev = pCurr = pos;
		pPrevAngs = pCurrAngs = (
			Normalize180(angle),
			Normalize180(pitch),
			Normalize180(roll));
	}

	//============================
	// Move (ACS utility)
	//============================
	static void Move (int platTid, double offX, double offY, double offZ, int newTime, double offAng = 0, double offPi = 0, double offRo = 0)
	{
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		FCW_Platform plat;
		while (plat = FCW_Platform(it.Next()))
		{
			plat.CommonACSSetup(newTime);
			plat.pNext = plat.pNextNext = plat.Vec3Offset(offX, offY, offZ);
			plat.pNextAngs = plat.pNextNextAngs = plat.pCurrAngs + (offAng, offPi, offRo);
		}
	}

	//============================
	// MoveTo (ACS utility)
	//============================
	static void MoveTo (int platTid, double newX, double newY, double newZ, int newTime, double offAng = 0, double offPi = 0, double offRo = 0)
	{
		//ACS itself has no 'vector3' variable type so it has to be 3 doubles (floats/fixed point numbers)
		vector3 newPos = (newX, newY, newZ);
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		FCW_Platform plat;
		while (plat = FCW_Platform(it.Next()))
		{
			plat.CommonACSSetup(newTime);
			plat.pNext = plat.pNextNext = plat.pos + level.Vec3Diff(plat.pos, newPos); //Make it portal aware
			plat.pNextAngs = plat.pNextNextAngs = plat.pCurrAngs + (offAng, offPi, offRo);
		}
	}

	//============================
	// MoveToSpot (ACS utility)
	//============================
	static void MoveToSpot (int platTid, int spotTid, int newTime)
	{
		//This is the only place you can make a platform use any actor as a travel destination
		let it = level.CreateActorIterator(spotTid);
		Actor spot = it.Next();
		if (!spot)
			return; //No spot? Nothing to do

		it = level.CreateActorIterator(platTid, "FCW_Platform");
		FCW_Platform plat;
		while (plat = FCW_Platform(it.Next()))
		{
			plat.CommonACSSetup(newTime);
			plat.pNext = plat.pNextNext = plat.pos + plat.Vec3To(spot); //Make it portal aware
			plat.pNextAngs = plat.pNextNextAngs = plat.pCurrAngs + (
				DeltaAngle(plat.pCurrAngs.x, spot.angle),
				DeltaAngle(plat.pCurrAngs.y, spot.pitch),
				DeltaAngle(plat.pCurrAngs.z, spot.roll));
		}
	}

	//============================
	// IsMoving (ACS utility)
	//============================
	static bool IsMoving (int platTid)
	{
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		let plat = FCW_Platform(it.Next());

		//When checking group members we only care about the origin.
		//Either "every member is moving" or "every member is not moving."
		if (plat && plat.group && plat.group.origin)
			plat = plat.group.origin;

		return (plat && plat.bActive && (
			plat.pos != plat.oldPos ||
			plat.angle != plat.oldAngle ||
			plat.pitch != plat.oldPitch ||
			plat.roll != plat.oldRoll) );
	}

	//============================
	// IsBlocked (ACS utility)
	//============================
	static bool IsBlocked (int platTid)
	{
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		let plat = FCW_Platform(it.Next());

		//When checking group members we only care about the origin.
		//Either "every member is blocked" or "every member is not blocked."
		if (plat && plat.group && plat.group.origin)
			plat = plat.group.origin;

		return (plat && plat.bActive && plat.bPlatBlocked);
	}

	//============================
	// SetTimeUnitTo* (ACS utility)
	//============================
	static void SetTimeUnitToOctics (int platTid)
	{
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		Actor plat;
		while (plat = it.Next())
			plat.args[ARG_TIMEUNIT] = TIMEUNIT_OCTICS;
	}
	static void SetTimeUnitToTics (int platTid)
	{
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		Actor plat;
		while (plat = it.Next())
			plat.args[ARG_TIMEUNIT] = TIMEUNIT_TICS;
	}
	static void SetTimeUnitToSeconds (int platTid)
	{
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		Actor plat;
		while (plat = it.Next())
			plat.args[ARG_TIMEUNIT] = TIMEUNIT_SECS;
	}
}

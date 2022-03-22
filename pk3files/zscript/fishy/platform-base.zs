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
		//For more info:
		//https://zdoom.org/wiki/Editor_keys
		//https://zdoom.org/wiki/Making_configurable_actors_in_DECORATE

		//$Arg0 Target
		//$Arg0Type 14
		//$Arg0Tooltip Must be a interpolation point (path to follow) or another platform (to attach to).

		//$Arg1 Options
		//$Arg1Type 12
		//Yes, this enum definition has to be on one line
		//$Arg1Enum {1 = "Linear path"; 2 = "Use target angle"; 4 = "Use target pitch"; 8 = "Use target roll"; 16 = "Face movement direction"; 32 = "Don't clip against geometry and other platforms"; 64 = "Start active"; 128 = "Mirror group origin's movement";}
		//$Arg1Tooltip NOTE: When being moved as part of a group, only flags 2, 4, 8 and 32 have any effect. Flag 128 only makes sense if in a group.

		//$Arg2 Travel/Hold time type
		//$Arg2Type 11
		//$Arg2Enum {0 = "Octics (default)"; 1 = "Tics"; 2 = "Seconds";}
		//$Arg2Tooltip Here you can specify travel time and hold time to be interpreted as something other than octics.\nNOTE: Does nothing if attached to another platform.

		//$Arg3 Crush Damage
		//$Arg3Tooltip The damage is applied once per 4 tics.

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

	static FCW_PlatformGroup Create ()
	{
		let group = new("FCW_PlatformGroup");
		group.members.Clear();
		group.index = 0;
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

	void VerifyMembers (FCW_Platform caller)
	{
		//Ensure 'caller', who already points to this group, is actually a member
		if (members.Find(caller) >= members.Size())
			members.Push(caller);

		//Ensure all members point to this group
		for (let plat = GetFirst(); plat; plat = GetNext())
			plat.group = self;
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
		ARG_TARGET		= 0,
		ARG_OPTIONS		= 1,
		ARG_TIMETYPE	= 2,
		ARG_CRUSHDMG	= 3,

		//For "ARG_OPTIONS"
		OPTFLAG_LINEAR			= 1,
		OPTFLAG_ANGLE			= 2,
		OPTFLAG_PITCH			= 4,
		OPTFLAG_ROLL			= 8,
		OPTFLAG_FACEMOVE		= 16,
		OPTFLAG_IGNOREGEO		= 32,
		OPTFLAG_STARTACTIVE		= 64,
		OPTFLAG_MIRROR			= 128,

		//For "ARG_TIMETYPE"
		OPT_TIMEINTICS		= 1,
		OPT_TIMEINSECS		= 2,

		//"InterpolationPoint" args (that we check)
		NODEARG_TRAVELTIME	= 1,
		NODEARG_HOLDTIME	= 2,
	};

	vector3 oldPos;
	double oldAngle;
	double oldPitch;
	double oldRoll;
	double time, timeFrac;
	int holdTime;
	bool bJustStepped;
	bool bPlatBlocked; //Only useful for ACS. (See utility functions below.)
	bool bPlatInMove; //No collision between a platform and its riders during said platform's move.
	InterpolationPoint currNode, firstNode;
	InterpolationPoint prevNode, firstPrevNode;
	Array<Actor> riders;
	FCW_PlatformGroup group;
	vector3 groupPoint;
	double groupAngle;
	double groupPitch;
	double groupRoll;

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
		time = timeFrac = 0.0;
		holdTime = 0;
		bJustStepped = false;
		bPlatBlocked = false;
		bPlatInMove = false;
		currNode = firstNode = null;
		prevNode = firstPrevNode = null;
		riders.Clear();
		group = null;
		groupPoint = (0, 0, 0);
		groupAngle = 0.0;
		groupPitch = 0.0;
		groupRoll = 0.0;

		pCurr = pPrev = pNext = pNextNext = (0, 0, 0);
		pCurrAngs = pPrevAngs = pNextAngs = pNextNextAngs = (0, 0, 0);
	}

	//============================
	// PostBeginPlay (override)
	//============================
	override void PostBeginPlay ()
	{
		bDormant = true;
		if (!args[ARG_TARGET])
			return; //Print no warnings if we're not supposed to look for anything

		String prefix = "\ckPlatform class '" .. GetClassName() .. "' with tid " .. tid .. ":\nat position " .. pos .. ":\n";
		if (args[ARG_TARGET] == tid)
		{
			Console.Printf(prefix .. "Is targeting itself.");
			return;
		}

		let it = level.CreateActorIterator(args[ARG_TARGET]);
		Actor mo = it.Next();
		while (mo && !(mo is "InterpolationPoint") && !(mo is "FCW_Platform"))
			mo = it.Next();

		if (!mo)
		{
			Console.Printf(prefix .. "Can't find suitable target with tid " .. args[ARG_TARGET] .. ".\nTarget must be a interpolation point (path to follow) or another platform (to attach to).");
			return;
		}

		if (mo is "FCW_Platform")
		{
			let plat = FCW_Platform(mo);
			if (plat.group) //Target is in its own group?
			{
				if (!group) //We don't have a group?
					plat.group.Add(self);
				else if (plat.group != group) //Both are in different groups?
					plat.group.MergeWith(group);
			}
			else if (group) //We're in a group but target doesn't have a group?
			{
				group.Add(plat);
			}
			else //Neither are in a group
			{
				let newGroup = FCW_PlatformGroup.Create();
				newGroup.Add(self);
				newGroup.Add(plat);
			}
			groupPoint = pos;
			groupAngle = angle;
			groupPitch = pitch;
			groupRoll = roll;

			//Get going if there's an active platform
			//and we ticked after it.
			for (let member = group.GetFirst(); member; member = group.GetNext())
			{
				if (!member.bDormant)
				{
					//Why does this detect DORMANT as false when it's not???
				}
			}
			return;
		}
		firstNode = InterpolationPoint(mo);

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
		if (pushForce.z != 0.0 && Distance2D(pushed) >= radius + pushed.radius) //Out of range?
			pushForce.z = 0.0;

		if (pushForce ~== (0, 0, 0))
			return;

		if (pos.xy != pushed.pos.xy && pushForce.xy != (0, 0))
		{
			double delta = DeltaAngle(VectorAngle(pushForce.x, pushForce.y), AngleTo(pushed));
			if (delta > 90.0 || delta < -90.0)
				pushForce.xy = RotateVector(pushForce.xy, delta); //Push away from platform's center
		}
		pushed.vel += pushForce;

		if (args[ARG_CRUSHDMG] <= 0)
			return;

		let oldZ = pushed.pos.z;
		pushed.AddZ(pushForce.z);
		bool fits = pushed.CheckMove(pushed.Vec2Offset(pushForce.x, pushForce.y));
		pushed.SetZ(oldZ);

		if (!fits)
			CrushObstacle(pushed);
	}

	//============================
	// SetTimeFraction
	//============================
	private void SetTimeFraction (int newTime)
	{
		switch (args[ARG_TIMETYPE])
		{
			case OPT_TIMEINTICS:
				timeFrac = 1.0 / max(1, newTime); //Interpret 'newTime' as tics
				break;
			case OPT_TIMEINSECS:
				timeFrac = 1.0 / (max(1, newTime) * TICRATE); //Interpret 'newTime' as seconds
				break;
			default:
				timeFrac = 8.0 / (max(1, newTime) * TICRATE); //Interpret 'newTime' as octics
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

		switch (args[ARG_TIMETYPE])
		{
			case OPT_TIMEINTICS:
				holdTime = level.mapTime + newTime; //Interpret 'newTime' as tics
				break;
			case OPT_TIMEINSECS:
				holdTime = level.mapTime + newTime * TICRATE; //Interpret 'newTime' as seconds
				break;
			default:
				holdTime = level.mapTime + newTime * TICRATE / 8; //Interpret 'newTime' as octics
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
	// GetNewRiders
	//============================
	private bool GetNewRiders (bool ignoreObs, bool laxZCheck)
	{
		//In addition to fetching riders, this is where corpses get crushed, too. (Items won't get destroyed.)
		//Returns false if an actor is completely stuck inside platform.

		double top = pos.z + height;
		Array<Actor> miscResults; //The actors on top of the riders (We'll move those, too)
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

			//Due to how the engine handles actor-to-actor interactions
			//we can only carry things with the +CANPASS or the
			//+SPECIAL flag. Anything else will just fall through.
			//Even when we have +ACTLIKEBRIDGE.
			bool canCarry = (!(mo is "FCW_Platform") && //Platforms shouldn't carry other platforms.
				!mo.bFloorHugger && !mo.bCeilingHugger && //Don't bother with floor/ceiling huggers.
				(mo.bCanPass || mo.bSpecial));

			bool oldRider = (riders.Find(mo) < riders.Size());
			if (mo is "FCW_Platform")
				otherPlats.Push(FCW_Platform(mo));

			//Check XY overlap
			double blockDist = radius + mo.radius;
			if (abs(it.position.x - mo.pos.x) < blockDist && abs(it.position.y - mo.pos.y) < blockDist)
			{
				//'laxZCheck' makes anything above our 'top' legit
				if (mo.pos.z >= top && (laxZCheck || mo.pos.z <= top + 1.0)) //On top of us?
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
						let moOldZ = mo.pos.z;
						if (!(mo is "FCW_Platform") && top - mo.pos.z <= mo.maxStepHeight)
						{
							mo.SetZ(top);
							blocked = !mo.CheckMove(mo.pos.xy);
						}
						if (blocked)
						{
							if (!(mo is "FCW_Platform"))
							{
								mo.SetZ(moOldZ);
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
						if (canCarry && !oldRider)
							onTopOfMe.Push(mo);
					}
					continue;
				}
			}

			if (canCarry && !oldRider)
				miscResults.Push(mo); //We'll compare this later against the riders
		}

		for (int i = 0; i < corpses.Size(); ++i)
			corpses[i].Grind(false);

		//Do NOT take other platforms' riders! Unless...
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
			for (int i = 0; i < miscResults.Size(); ++i)
			{
				if (plat.riders.Find(miscResults[i]) < plat.riders.Size())
					miscResults.Delete(i--);
			}
		}
		riders.Append(onTopOfMe);

		//Now figure out which of the misc actors are on top of/stuck inside
		//established riders.
		for (int i = 0; i < riders.Size(); ++i)
		{
			let mo = riders[i];
			double moTop = mo.pos.z + mo.height + 1.0;

			for (int iOther = 0; iOther < miscResults.Size(); ++iOther)
			{
				let otherMo = miscResults[iOther];

				if (moTop > otherMo.pos.z && otherMo.pos.z + otherMo.height > mo.pos.z && //Is 'otherMo' on top of or stuck inside 'mo'?
					mo.Distance2D(otherMo) < mo.radius + otherMo.radius) //Within XY range?
				{
					miscResults.Delete(iOther--); //Don't compare this one against other riders anymore
					riders.Push(otherMo);
				}
			}
		}
		return true;
	}

	//============================
	// MoveRiders
	//============================
	private bool MoveRiders (bool ignoreObs, bool teleMove)
	{
		//Returns false if a blocked rider would block the platform's movement

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
				(cos(angle-90.0)*roDelta, sin(angle-90.0)*roDelta); //Right/left
		}

		Array<double> preMovePos; //Sadly we can't have a vector2/3 dyn array
		for (int i = 0; i < riders.Size(); ++i)
		{
			let mo = riders[i];
			let moOldPos = mo.pos;

			vector3 offset = level.Vec3Diff(oldPos, mo.pos);
			offset.xy = (offset.x*c - offset.y*s, offset.x*s + offset.y*c); //Rotate it
			offset.xy += piAndRoOffset;
			vector3 moNewPos = level.Vec3Offset(pos, offset);

			//TryMove() has its own internal handling of portals which is
			//a problem if 'moNewPos' is already through a portal from the platform's
			//position. What it wants/needs is a offsetted position from 'mo' assuming
			//no portals have been crossed yet.
			if (!teleMove)
				moNewPos = mo.pos + level.Vec3Diff(mo.pos, moNewPos);

			//Handle z discrepancy
			if (moNewPos.z < top && moNewPos.z + mo.height >= top)
				moNewPos.z = top;

			let moOldNoDropoff = mo.bNoDropoff;
			mo.bNoDropoff = false;
			bool moved;
			if (teleMove)
			{
				mo.SetOrigin(moNewPos, false);
				moved = mo.CheckMove(moNewPos.xy);
			}
			else
			{
				mo.SetZ(moNewPos.z);
				moved = mo.TryMove(moNewPos.xy, 1);
			}

			//Take into account riders getting Thing_Remove()'d
			//when they activate lines.
			if (!mo || mo.bDestroyed)
			{
				riders.Delete(i--);
				continue;
			}
			mo.bNoDropoff = moOldNoDropoff;

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
				mo.SetOrigin(moOldPos, true);

				//This rider will be 'solid' for the others
				mo.A_ChangeLinkFlags(addToBmap);
				riders.Delete(i--);

				//See if it would block the platform
				double moTop = mo.pos.z + mo.height;
				bool blocked = ( !ignoreObs && CollisionFlagChecks(mo, self) &&
					moTop > self.pos.z && top > mo.pos.z && //Overlaps Z?
					mo.Distance2D(self) < mo.radius + self.radius && //Within XY range?
					mo.CanCollideWith(self, false) && self.CanCollideWith(mo, true) );

				//See if the ones we moved already will collide with this one
				//and if yes, move them back to their old positions.
				//(If the platform's "blocked" then move everyone back unconditionally.)
				for (int iOther = 0; iOther <= i; ++iOther)
				{
					let otherMo = riders[iOther];
					if ( !blocked && ( !CollisionFlagChecks(otherMo, mo) ||
						moTop <= otherMo.pos.z || otherMo.pos.z + otherMo.height <= mo.pos.z || //No Z overlap?
						otherMo.Distance2D(mo) >= otherMo.radius + mo.radius || //Out of XY range?
						!otherMo.CanCollideWith(mo, false) || !mo.CanCollideWith(otherMo, true) ) )
					{
						continue;
					}

					//Put 'otherMo' back at its old position
					vector3 otherOldPos = (preMovePos[iOther*3], preMovePos[(iOther*3)+1], preMovePos[(iOther*3)+2]);
					otherMo.SetOrigin(otherOldPos, true);

					otherMo.A_ChangeLinkFlags(addToBmap);
					preMovePos.Delete(iOther*3, 3);
					riders.Delete(iOther--);
					i--;
				}

				if (blocked)
				{
					PushObstacle(mo, level.Vec3Diff(oldPos, pos));
					for (i = 0; i < riders.Size(); ++i)
						riders[i].A_ChangeLinkFlags(addToBmap); //Handle those that didn't get the chance to move
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
		//The main purpose of this is to keep walkers away from platform's edge.
		//The AI's native handling of trying not to fall off of other actors
		//just isn't good enough.

		bool hasMoved = (!bDormant && (
			pos != oldPos ||
			angle != oldAngle ||
			pitch != oldPitch ||
			roll != oldRoll));
		vector2 pushForce = (0, 0);
		bool piPush = (args[ARG_OPTIONS] & OPTFLAG_PITCH);
		bool roPush = (args[ARG_OPTIONS] & OPTFLAG_ROLL);

		//If we're not moving and we interpolate our pitch/roll,
		//and our pitch/roll is currently steep, then push things off of us.
		if (!hasMoved && !(level.mapTime & 7)) //Push is applied once per 8 tics.
		{
			if ((piPush || roPush) && !(level.mapTime & 63))
				GetNewRiders(true, false); //Get something to push off

			if (piPush && riders.Size())
			{
				pitch = Normalize180(pitch);
				if (abs(pitch) >= 45.0 && abs(pitch) <= 135.0)
				{
					vector2 newPush = (cos(angle), sin(angle)); //Push front or back
					pushForce += ((pitch > 0.0 && pitch < 90.0) || pitch < -90.0) ? newPush : -newPush;
				}
			}
			if (roPush && riders.Size())
			{
				roll = Normalize180(roll);
				if (abs(roll) >= 45.0 && abs(roll) <= 135.0)
				{
					vector2 newPush = (cos(angle-90.), sin(angle-90.)); //Push right or left
					pushForce += ((roll > 0.0 && roll < 90.0) || roll < -90.0) ? newPush : -newPush;
				}
			}
		}

		double top = pos.z + height;

		for (int i = 0; i < riders.Size(); ++i)
		{
			let mo = riders[i];
			if (!mo || mo.bDestroyed ||
				mo.bNoBlockmap ||
				mo.bFloorHugger || mo.bCeilingHugger ||
				(!mo.bCanPass && !mo.bSpecial))
			{
				riders.Delete(i--);
				continue;
			}

			//'floorZ' can be the top of a 3D floor that's right below an actor.
			if (mo.pos.z < top - 1.0 || mo.floorZ > top + 1.0) //Is below us or stuck in us or there's a 3D floor between us?
			{
				riders.Delete(i--);
				continue;
			}

			double dist = Distance2D(mo);
			if (dist >= radius + mo.radius) //Is out of XY range?
			{
				riders.Delete(i--);
				continue;
			}

			mo.vel.xy += pushForce;
			if (!mo.bIsMonster || mo.bNoGravity || mo.bFloat || !mo.speed) //Is not a walking monster?
			{
				if (!hasMoved && pushForce ~== (0, 0))
					riders.Delete(i--);
				continue;
			}
			if (mo.bDropoff || mo.bJumpDown) //Is supposed to fall off of tall drops or jump down?
			{
				if (!hasMoved && pushForce ~== (0, 0))
					riders.Delete(i--);
				continue;
			}

			//See if we should keep it away from the edge
			if (mo.tics != 1 && mo.tics != 0)
				continue; //Don't bother if it's not about to change states

			if (pushForce != (0, 0))
				continue; //Not if we're pushing it

			if (mo.pos.z > top + 1.0)
				continue; //Not exactly on top of us

			if (dist < radius - mo.speed)
				continue; //Not close to platform's edge

			if (mo.pos.z - mo.curSector.NextLowestFloorAt(mo.pos.x, mo.pos.y, mo.pos.z) <= mo.maxDropoffHeight)
				continue; //Monster is close to the ground (which includes 3D floors) so let it walk off

			//Make your bog-standard idTech1 AI
			//that uses A_Chase() or A_Wander()
			//walk towards the platform's center.
			//NOTE: This isn't fool proof if there
			//are multiple riders moving on the
			//same platform at the same time.
			mo.moveDir = int(mo.AngleTo(self) / 45) & 7;
			if (mo.moveCount < 1)
				mo.moveCount = 1;
		}

		if (bDormant)
			return;

		if (group)
		for (let plat = group.GetFirst(); plat; plat = group.GetNext())
		{
			if (plat != self)
				plat.HandleOldRiders();
		}
	}

	//============================
	// MaybeLerp
	//============================
	private double MaybeLerp (double p1, double p2)
	{
		return (p1 == p2) ? p1 : (p1 + time * (p2 - p1));
	}

	//============================
	// MaybeSplerp
	//============================
	private double MaybeSplerp (double p1, double p2, double p3, double p4)
	{
		if (p2 == p3)
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
	// PlatTryMove
	//============================
	private bool PlatTryMove (vector3 newPos)
	{
		if (pos == newPos)
			return true;

		bPlatInMove = true; //Temporarily don't clip against riders
		SetZ(newPos.z);
		bool moved = TryMove(newPos.xy, 1);

		if (!moved && blockingMobj && !(blockingMobj is "FCW_Platform"))
		{
			let mo = blockingMobj;
			let moOldZ = mo.pos.z;
			let moNewZ = newPos.z + self.height;

			//Try to set the obstacle on top of us if its 'maxStepHeight' allows it
			if (moNewZ > moOldZ && moNewZ - moOldZ <= mo.maxStepHeight)
			{
				mo.SetZ(moNewZ);
				if (mo.CheckMove(mo.pos.xy)) //Obstacle fits at new Z even before we moved?
					moved = TryMove(newPos.xy, 1); //Try one more time
			}

			if (!moved) //Blocked by actor that isn't a platform?
			{
				bPlatInMove = false;
				mo.SetZ(moOldZ);
				self.SetZ(oldPos.z);
				PushObstacle(mo, level.Vec3Diff(oldPos, newPos));
				return false;
			}
		}
		bPlatInMove = false;

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
	// Interpolate
	//============================
	private bool Interpolate ()
	{
		//A heavily modified version of the
		//original function from PathFollower.

		Vector3 dpos = (0, 0, 0);
		if ((args[ARG_OPTIONS] & OPTFLAG_FACEMOVE) && time > 0.0)
			dpos = pos;

		vector3 newPos;
		if (args[ARG_OPTIONS] & OPTFLAG_LINEAR)
		{
			newPos.x = MaybeLerp(pCurr.x, pNext.x);
			newPos.y = MaybeLerp(pCurr.y, pNext.y);
			newPos.z = MaybeLerp(pCurr.z, pNext.z);
		}
		else //Spline
		{
			newPos.x = MaybeSplerp(pPrev.x, pCurr.x, pNext.x, pNextNext.x);
			newPos.y = MaybeSplerp(pPrev.y, pCurr.y, pNext.y, pNextNext.y);
			newPos.z = MaybeSplerp(pPrev.z, pCurr.z, pNext.z, pNextNext.z);
		}

		//Do a blockmap search once per tic if we're in motion.
		//Otherwise, do (at most) two searches per 64 tics (almost 2 seconds).
		//The first non-motion search can happen in HandleOldRiders().
		//The second non-motion search will happen here 32 tics after the first one.
		if (newPos != pos || !((level.mapTime + 32) & 63))
		{
			if (!GetNewRiders(false, false))
				return false;
		}

		let oldPGroup = curSector.portalGroup;
		if (!PlatTryMove(newPos))
			return false;

		if (args[ARG_OPTIONS] & (OPTFLAG_ANGLE | OPTFLAG_PITCH | OPTFLAG_ROLL))
		{
			if (args[ARG_OPTIONS] & OPTFLAG_FACEMOVE)
			{
				if (args[ARG_OPTIONS] & OPTFLAG_LINEAR)
				{
					dpos = pNext - pCurr;
				}
				else if (time > 0.0) //Spline
				{
					dpos = newPos - dpos;
				}
				else if (args[ARG_OPTIONS] & (OPTFLAG_ANGLE | OPTFLAG_PITCH))
				{	//Spline but with time <= 0.0
					dpos = newPos;
					time = timeFrac;
					newPos.x = MaybeSplerp(pPrev.x, pCurr.x, pNext.x, pNextNext.x);
					newPos.y = MaybeSplerp(pPrev.y, pCurr.y, pNext.y, pNextNext.y);
					newPos.z = MaybeSplerp(pPrev.z, pCurr.z, pNext.z, pNextNext.z);
					time = 0.0;
					dpos = newPos - dpos;
					newPos -= dpos;
				}

				//Adjust angle
				if (args[ARG_OPTIONS] & OPTFLAG_ANGLE)
					angle = VectorAngle(dpos.x, dpos.y);

				//Adjust pitch
				if (args[ARG_OPTIONS] & OPTFLAG_PITCH)
				{
					double dist = dpos.xy.Length();
					pitch = dist ? VectorAngle(dist, -dpos.z) : 0.0;
				}
				//Adjust roll
				if (args[ARG_OPTIONS] & OPTFLAG_ROLL)
					roll = 0.0;
			}
			else
			{
				if (args[ARG_OPTIONS] & OPTFLAG_LINEAR)
				{
					//Interpolate angle
					if (args[ARG_OPTIONS] & OPTFLAG_ANGLE)
						angle = MaybeLerp(pCurrAngs.x, pNextAngs.x);

					//Interpolate pitch
					if (args[ARG_OPTIONS] & OPTFLAG_PITCH)
						pitch = MaybeLerp(pCurrAngs.y, pNextAngs.y);

					//Interpolate roll
					if (args[ARG_OPTIONS] & OPTFLAG_ROLL)
						roll = MaybeLerp(pCurrAngs.z, pNextAngs.z);
				}
				else //Spline
				{
					//Interpolate angle
					if (args[ARG_OPTIONS] & OPTFLAG_ANGLE)
						angle = MaybeSplerp(pPrevAngs.x, pCurrAngs.x, pNextAngs.x, pNextNextAngs.x);

					//Interpolate pitch
					if (args[ARG_OPTIONS] & OPTFLAG_PITCH)
						pitch = MaybeSplerp(pPrevAngs.y, pCurrAngs.y, pNextAngs.y, pNextNextAngs.y);

					//Interpolate roll
					if (args[ARG_OPTIONS] & OPTFLAG_ROLL)
						roll = MaybeSplerp(pPrevAngs.z, pCurrAngs.z, pNextAngs.z, pNextNextAngs.z);
				}
			}
		}

		if (!MoveRiders(false, false))
		{
			SetOrigin(oldPos, true);
			angle = oldAngle;
			pitch = oldPitch;
			roll = oldRoll;
			return false;
		}

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
		if (!MovePlatformGroup(false))
			return false;

		return true;
	}

	//============================
	// UpdateGroupInfo
	//============================
	private void UpdateGroupInfo ()
	{
		if (group)
		for (let plat = group.GetFirst(); plat; plat = group.GetNext())
		{
			if (plat != self)
				plat.bDormant = true;

			plat.groupPoint = plat.pos;
			plat.groupAngle = plat.angle;
			plat.groupPitch = plat.pitch;
			plat.groupRoll = plat.roll;
		}
	}

	//============================
	// MovePlatformGroup
	//============================
	private bool MovePlatformGroup (bool teleMove)
	{
		if (!group)
			return true;

		double delta = DeltaAngle(groupAngle, angle);
		double piDelta = DeltaAngle(groupPitch, pitch);
		double roDelta = DeltaAngle(groupRoll, roll);

		double cFirst = 0.0, sFirst = 0.0;
		double cY, sY;
		double cP, sP;
		double cR, sR;
		double cLast, sLast;

		for (let plat = group.GetFirst(); plat; plat = group.GetNext())
		{
			if (plat == self)
				continue;

			plat.bDormant = true; //We're the primary thinker
			plat.oldPos = plat.pos;
			plat.oldAngle = plat.angle;
			plat.oldPitch = plat.pitch;
			plat.oldRoll = plat.roll;
			bool changeAng = (plat.args[ARG_OPTIONS] & OPTFLAG_ANGLE);
			bool changePi = (plat.args[ARG_OPTIONS] & OPTFLAG_PITCH);
			bool changeRo = (plat.args[ARG_OPTIONS] & OPTFLAG_ROLL);

			vector3 newPos;
			if (plat.args[ARG_OPTIONS] & OPTFLAG_MIRROR) //No rotations happen here
			{
				//The way we mirror movement is by getting the offset going
				//from the origin's current position to its 'groupPoint'
				//and using that to get a offsetted position from
				//the attached platform's 'groupPoint'.
				//So we pretty much always go in the opposite direction
				//using our 'groupPoint' as a reference point.
				vector3 offset = level.Vec3Diff(pos, groupPoint);
				newPos = level.Vec3Offset(plat.groupPoint, offset);

				if (changeAng)
					plat.angle = Normalize180(plat.groupAngle - delta);
				if (changePi)
					plat.pitch = Normalize180(plat.groupPitch - piDelta);
				if (changeRo)
					plat.roll = Normalize180(plat.groupRoll - roDelta);
			}
			else //Non-mirror movement. Rotations happens here.
			{
				if (cFirst == sFirst) //Not called cos() and sin() yet?
				{
					cFirst = cos(-groupAngle); sFirst = sin(-groupAngle);
					cY = cos(delta);   sY = sin(delta);
					cP = cos(piDelta); sP = sin(piDelta);
					cR = cos(roDelta); sR = sin(roDelta);
					cLast = cos(groupAngle);   sLast = sin(groupAngle);
				}
				vector3 offset = level.Vec3Diff(groupPoint, plat.groupPoint);

				//Rotate the offset. The order here matters.
				offset.xy = (offset.x*cFirst - offset.y*sFirst, offset.x*sFirst + offset.y*cFirst); //Rotate to 0 angle degrees of origin
				offset = (offset.x, offset.y*cR - offset.z*sR, offset.y*sR + offset.z*cR);  //X axis (roll)
				offset = (offset.x*cP + offset.z*sP, offset.y, -offset.x*sP + offset.z*cP); //Y axis (pitch)
				offset = (offset.x*cY - offset.y*sY, offset.x*sY + offset.y*cY, offset.z);  //Z axis (yaw/angle)
				offset.xy = (offset.x*cLast - offset.y*sLast, offset.x*sLast + offset.y*cLast); //Rotate back to origin's 'groupAngle'

				newPos = level.Vec3Offset(pos, offset);

				if (changeAng)
					plat.angle = Normalize180(plat.groupAngle + delta);

				if (changePi || changeRo)
				{
					double diff = DeltaAngle(angle, plat.angle);
					double c = cos(diff), s = sin(diff);
					if (changePi)
						plat.pitch = Normalize180(plat.groupPitch + piDelta*c - roDelta*s);
					if (changeRo)
						plat.roll = Normalize180(plat.groupRoll + piDelta*s + roDelta*c);
				}
			}

			//Do a blockmap search once per tic if we're in motion.
			//Otherwise, do (at most) two searches per 64 tics (almost 2 seconds).
			//The first non-motion search can happen in HandleOldRiders().
			//The second non-motion search will happen here 32 tics after the first one.
			if (newPos != plat.pos || !((level.mapTime + 32) & 63))
			{
				if (!plat.GetNewRiders(teleMove, teleMove))
				{
					plat.angle = plat.oldAngle;
					plat.pitch = plat.oldPitch;
					plat.roll = plat.oldRoll;
					return false;
				}
			}

			if (teleMove)
			{
				plat.SetOrigin(newPos, false);
			}
			else
			{
				newPos = plat.pos + level.Vec3Diff(plat.pos, newPos); //For TryMove()
				if (!plat.PlatTryMove(newPos))
				{
					plat.angle = plat.oldAngle;
					plat.pitch = plat.oldPitch;
					plat.roll = plat.oldRoll;
					return false;
				}
			}

			if (!plat.MoveRiders(teleMove, teleMove))
			{
				plat.SetOrigin(plat.oldPos, true);
				plat.angle = plat.oldAngle;
				plat.pitch = plat.oldPitch;
				plat.roll = plat.oldRoll;
				return false;
			}
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
		bDormant = true;
	}

	//============================
	// Activate (override)
	//============================
	override void Activate (Actor activator)
	{
		if (bDormant)
		{
			currNode = firstNode;
			prevNode = firstPrevNode;

			if (currNode)
			{
				CallNodeSpecials();
				if (bDestroyed || !currNode || currNode.bDestroyed)
					return; //Abort if we or the node got Thing_Remove()'d

				UpdateGroupInfo();
				GetNewRiders(true, true);
				SetOrigin(currNode.pos, false);
				if (args[ARG_OPTIONS] & OPTFLAG_ANGLE)
					angle = currNode.angle;
				if (args[ARG_OPTIONS] & OPTFLAG_PITCH)
					pitch = currNode.pitch;
				if (args[ARG_OPTIONS] & OPTFLAG_ROLL)
					roll = currNode.roll;
				time = 0.0;
				holdTime = 0;
				bJustStepped = true;
				bDormant = false;
				SetInterpolationCoordinates();
				SetTimeFraction(currNode.args[NODEARG_TRAVELTIME]);
				MoveRiders(true, true);
				MovePlatformGroup(true);
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

		//Advance states
		if (tics != -1 && --tics <= 0)
		{
			if (!SetState(curState.nextState))
				return; //Freed itself
		}

		if (bDormant)
			return;

		if (group)
			group.VerifyMembers(self);

		HandleOldRiders();

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
			return;

		if (!Interpolate())
		{
			bPlatBlocked = true;
			return;
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
					return; //Our node got Thing_Remove()'d
				}
				SetInterpolationCoordinates();
				SetTimeFraction(currNode.args[NODEARG_TRAVELTIME]);
			}

			if (!currNode || !currNode.next)
				Deactivate(self);
			else if ((args[ARG_OPTIONS] & OPTFLAG_LINEAR) && !currNode.next.next)
				Deactivate(self);
		}
	}

	//============================
	// CommonACSSetup
	//============================
	private void CommonACSSetup (int newTime, int timeType)
	{
		UpdateGroupInfo();
		currNode = null; //Deactivate when done moving
		prevNode = null;
		time = 0.0;
		holdTime = 0;
		let savedArg = args[ARG_TIMETYPE];
		args[ARG_TIMETYPE] = timeType;
		SetTimeFraction(newTime);
		args[ARG_TIMETYPE] = savedArg;
		bDormant = false;
		pPrev = pCurr = pos;
		pPrevAngs = pCurrAngs = (
			Normalize180(angle),
			Normalize180(pitch),
			Normalize180(roll));
	}

	//============================
	// Move (ACS utility)
	//============================
	static void Move (int platTid, double offX, double offY, double offZ, int newTime, int timeType = OPT_TIMEINTICS, double offAng = 0.0, double offPi = 0.0, double offRo = 0.0)
	{
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		FCW_Platform plat;
		while (plat = FCW_Platform(it.Next()))
		{
			plat.CommonACSSetup(newTime, timeType);
			plat.pNext = plat.pNextNext = plat.Vec3Offset(offX, offY, offZ);
			plat.pNextAngs = plat.pNextNextAngs = plat.pCurrAngs + (offAng, offPi, offRo);
		}
	}

	//============================
	// MoveTo (ACS utility)
	//============================
	static void MoveTo (int platTid, double newX, double newY, double newZ, int newTime, int timeType = OPT_TIMEINTICS, double offAng = 0.0, double offPi = 0.0, double offRo = 0.0)
	{
		//ACS itself has no 'vector3' variable type so it has to be 3 doubles (floats/fixed point numbers)
		vector3 newPos = (newX, newY, newZ);
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		FCW_Platform plat;
		while (plat = FCW_Platform(it.Next()))
		{
			plat.CommonACSSetup(newTime, timeType);
			plat.pNext = plat.pNextNext = plat.pos + level.Vec3Diff(plat.pos, newPos); //Make it portal aware
			plat.pNextAngs = plat.pNextNextAngs = plat.pCurrAngs + (offAng, offPi, offRo);
		}
	}

	//============================
	// MoveToSpot (ACS utility)
	//============================
	static void MoveToSpot (int platTid, int spotTid, int newTime, int timeType = OPT_TIMEINTICS)
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
			plat.CommonACSSetup(newTime, timeType);
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
		return (plat && !plat.bDormant && (
			plat.pos != plat.oldPos ||
			plat.angle != plat.oldAngle ||
			plat.pitch != plat.oldPitch ||
			plat.roll != plat.oldRoll));
	}

	//============================
	// IsBlocked (ACS utility)
	//============================
	static bool IsBlocked (int platTid)
	{
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		let plat = FCW_Platform(it.Next());
		return (plat && !plat.bDormant && plat.bPlatBlocked);
	}
}

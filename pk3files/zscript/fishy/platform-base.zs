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
		//$Arg0Tooltip Must be 'Platform Interpolation Point' or GZDoom's 'Interpolation Point' class.\nWhichever is more convenient.\n'Interpolation Special' works with both.

		//$Arg1 Options
		//$Arg1Type 12
		//$Arg1Enum {1 = "Linear path"; 2 = "Use point angle / Group move: Rotate angle"; 4 = "Use point pitch / Group move: Rotate pitch"; 8 = "Use point roll / Group move: Rotate roll"; 16 = "Face movement direction"; 32 = "Don't clip against geometry and other platforms"; 64 = "Start active"; 128 = "Group move: Mirror group origin's movement";}
		//$Arg1Tooltip Anything with 'Group move' affects movement imposed by the group origin.\nIt does nothing for the group origin itself.\nThe 'group origin' is the platform that the others move with and orbit around.

		//$Arg2 Platform(s) To Group With
		//$Arg2Type 14

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

class FCW_PlatformNode : InterpolationPoint
{
	Default
	{
		//$Title Platform Interpolation Point

		//$Arg0 Next Point
		//$Arg0Type 14

		//$Arg1 Travel Time

		//$Arg2 Hold Time

		//$Arg3 Travel Time Unit
		//$Arg3Type 11
		//$Arg3Enum {0 = "Octics"; 1 = "Tics"; 2 = "Seconds";}

		//$Arg4 Hold Time Unit
		//$Arg4Type 11
		//$Arg4Enum {0 = "Octics"; 1 = "Tics"; 2 = "Seconds";}
	}
}

//Ultimate Doom Builder doesn't need to read the rest
//$GZDB_SKIP

extend class FCW_PlatformNode
{
	void PNodeFormChain ()
	{
		// The relevant differences from InterpolationPoint's FormChain() are:
		// 1) The archaic tid/hi-tid lookup is gone.
		// 2) The tid to look for is on a different argument.
		// 3) The pitch isn't clamped.

		for (FCW_PlatformNode node = self; node; node = FCW_PlatformNode(node.next))
		{
			if (node.bVisited)
				return;
			node.bVisited = true;

			let it = level.CreateActorIterator(node.args[0], "FCW_PlatformNode");
			do
			{
				node.next = FCW_PlatformNode(it.Next());
			} while (node.next == node); //Don't link to self

			if (!node.next && node.args[0])
				Console.Printf("\ckPlatform interpolation point with tid " .. node.tid .. " at position " ..node.pos ..
				":\ncannot find next platform interpolation point with tid " .. node.args[0] .. ".");
		}
	}
}

class FCW_PlatformGroup play
{
	Array<FCW_Platform> members;
	FCW_Platform origin;	//Called so because every other member orbits around and follows this one.
							//Also, the "origin" does most of the thinking for the other members. See Tick().

	static FCW_PlatformGroup Create ()
	{
		let group = new("FCW_PlatformGroup");
		group.members.Clear();
		group.origin = null;
		return group;
	}

	void Add (FCW_Platform plat)
	{
		plat.group = self;
		if (members.Find(plat) >= members.Size())
			members.Push(plat);
	}

	FCW_Platform GetMember (int index)
	{
		//Handle invalid entries
		while (index < members.Size() && !members[index])
			members.Delete(index);

		if (index < members.Size())
		{
			members[index].group = self; //Ensure members point to the correct group
			return members[index];
		}
		return null;
	}

	void MergeWith (FCW_PlatformGroup otherGroup)
	{
		for (int i = 0; i < otherGroup.members.Size(); ++i)
		{
			let plat = otherGroup.GetMember(i);
			if (plat)
				Add(plat);
		}
	}
}

extend class FCW_Platform
{
	enum ArgValues
	{
		ARG_NODETID			= 0,
		ARG_OPTIONS			= 1,
		ARG_GROUPTID		= 2,
		ARG_CRUSHDMG		= 3,

		//For "ARG_OPTIONS"
		OPTFLAG_LINEAR			= 1,
		OPTFLAG_ANGLE			= 2,
		OPTFLAG_PITCH			= 4,
		OPTFLAG_ROLL			= 8,
		OPTFLAG_FACEMOVE		= 16,
		OPTFLAG_IGNOREGEO		= 32,
		OPTFLAG_STARTACTIVE		= 64,
		OPTFLAG_MIRROR			= 128,

		//FCW_PlatformNode args that we check
		NODEARG_TRAVELTIME		= 1, //Also applies to InterpolationPoint
		NODEARG_HOLDTIME		= 2, //Ditto
		NODEARG_TRAVELTUNIT		= 3,
		NODEARG_HOLDTUNIT		= 4,

		//For FCW_PlatformNode's "NODEARG_TRAVELTUNIT" and "NODEARG_HOLDTUNIT"
		TIMEUNIT_OCTICS		= 0,
		TIMEUNIT_TICS		= 1,
		TIMEUNIT_SECS		= 2,
	};

	const TOPEPSILON = 1.0;

	vector3 oldPos;
	double oldAngle;
	double oldPitch;
	double oldRoll;
	double spawnZ; //This is not the same as spawnPoint.z
	double spawnPitch;
	double spawnRoll;
	double time, timeFrac;
	int holdTime;
	bool bActive;
	bool bJustStepped;
	bool bPlatBlocked;	//Only useful for ACS. (See utility functions below.)
	transient bool bPlatInMove; //No collision between a platform and its passengers during said platform's move.
	InterpolationPoint currNode, firstNode;
	InterpolationPoint prevNode, firstPrevNode;
	Array<Actor> passengers;
	FCW_PlatformGroup group;

	//Unlike PathFollower classes, our interpolations are done with
	//vector3 coordinates instead of checking InterpolationPoint positions.
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
		spawnZ = pos.z;
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
		passengers.Clear();
		group = null;

		pCurr = pPrev = pNext = pNextNext = (0, 0, 0);
		pCurrAngs = pPrevAngs = pNextAngs = pNextNextAngs = (0, 0, 0);
	}

	//============================
	// PostBeginPlay (override)
	//============================
	override void PostBeginPlay ()
	{
		Super.PostBeginPlay();

		String prefix = "\ckPlatform class '" .. GetClassName() .. "' with tid " .. tid .. " at position " .. pos .. ":\n";

		if (args[ARG_GROUPTID])
		{
			let it = level.CreateActorIterator(args[ARG_GROUPTID], "FCW_Platform");
			FCW_Platform plat;
			bool foundOne = false;
			while (plat = FCW_Platform(it.Next()))
			{
				if (plat != self)
					foundOne = true;

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

			if (!foundOne)
			{
				Console.Printf(prefix .. "Can't find platform(s) with tid " .. args[ARG_GROUPTID] .. " to group with.");
				prefix = "\ck";
			}
		}

		if (group && group.origin)
		{
			let ori = group.origin;
			if (ori.pos.xy != ori.spawnPoint.xy ||
				ori.pos.z != ori.spawnZ ||
				ori.angle != ori.spawnAngle ||
				ori.pitch != ori.spawnPitch ||
				ori.roll != ori.spawnRoll)
			{
				//If the group origin is already active then call MoveGroup() now.
				//This matters if the origin's first interpolation point has a defined hold time
				//because depending on who ticks first some members might have already moved
				//and some might have not.
				ori.MoveGroup(true);
			}
		}

		//Print no (additional) warnings if we're not supposed to have a interpolation point
		if (!args[ARG_NODETID])
		{
			//In case the mapper placed walking monsters on the platform
			//get something for HandleOldPassengers() to monitor.
			GetNewPassengers(true);
			return; 
		}

		let it = level.CreateActorIterator(args[ARG_NODETID], "InterpolationPoint");
		firstNode = InterpolationPoint(it.Next());
		if (!firstNode)
		{
			Console.Printf(prefix .. "Can't find interpolation point with tid " .. args[ARG_NODETID] .. ".");
			return;
		}

		//Verify the path has enough nodes
		if (firstNode is "FCW_PlatformNode")
			FCW_PlatformNode(firstNode).PNodeFormChain();
		else
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
			let node = firstNode;
			Array<InterpolationPoint> checkedNodes;
			while (node.next && node.next != firstNode && checkedNodes.Find(node) >= checkedNodes.Size())
			{
				checkedNodes.Push(node);
				node = node.next;
			}

			if (node.next == firstNode)
			{
				firstPrevNode = node;
			}
			else
			{
				firstPrevNode = firstNode;
				firstNode = firstNode.next;
			}
		}

		if (args[ARG_OPTIONS] & OPTFLAG_STARTACTIVE)
			Activate(self);
		else							//In case the mapper placed walking monsters on the platform
			GetNewPassengers(true);		//get something for HandleOldPassengers() to monitor.
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

		if (bPlatInMove && passengers.Find(other) < passengers.Size())
			return false;

		return true;
	}

	//============================
	// CollisionFlagChecks
	//============================
	static bool CollisionFlagChecks (Actor a, Actor b)
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
	static bool OverlapXY (Actor a, Actor b, double blockDist = 0)
	{
		if (!blockDist)
			blockDist = a.radius + b.radius;
		vector2 vec = level.Vec2Diff(a.pos.xy, b.pos.xy);
		return (abs(vec.x) < blockDist && abs(vec.y) < blockDist);
	}

	//============================
	// OverlapZ
	//============================
	static bool OverlapZ (Actor a, Actor b)
	{
		return (a.pos.z + a.height > b.pos.z &&
				b.pos.z + b.height > a.pos.z);
	}

	//============================
	// FitsAtPosition
	//============================
	static bool FitsAtPosition (Actor mo, vector3 testPos)
	{
		//Unlike TestMobjLocation(), CheckMove() takes into account
		//actors that have the flags FLOORHUGGER, CEILINGHUGGER
		//and CANTLEAVEFLOORPIC.

		let oldZ = mo.pos.z;
		mo.SetZ(testPos.z); //Because setting Z has an effect on CheckMove()'s outcome

		FCheckPosition tm;
		bool result = (mo.CheckMove(testPos.xy, 0, tm) &&
			testPos.z >= tm.floorZ &&				//This is something that TestMobjLocation() checks
			testPos.z + mo.height <= tm.ceilingZ);	//and that CheckMove() does not account for.

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
	private void SetTimeFraction ()
	{
		if (!currNode)
			return;

		int newTime = max(1, currNode.args[NODEARG_TRAVELTIME]);

		if (currNode is "FCW_PlatformNode")
		{
			switch (currNode.args[NODEARG_TRAVELTUNIT])
			{
				default:
				case TIMEUNIT_OCTICS:
					timeFrac = 8.0 / (newTime * TICRATE);
					break;
				case TIMEUNIT_TICS:
					timeFrac = 1.0 / newTime;
					break;
				case TIMEUNIT_SECS:
					timeFrac = 1.0 / (newTime * TICRATE);
					break;
			}
		}
		else // Old InterpolationPoint class, always in octics
		{
			timeFrac = 8.0 / (max(1, newTime) * TICRATE);
		}
	}

	//============================
	// SetHoldTime
	//============================
	private void SetHoldTime ()
	{
		if (!currNode)
			return;

		int newTime = currNode.args[NODEARG_HOLDTIME];
		if (newTime <= 0)
			return;

		if (currNode is "FCW_PlatformNode")
		{
			switch (currNode.args[NODEARG_HOLDTUNIT])
			{
				default:
				case TIMEUNIT_OCTICS:
					holdTime = level.mapTime + newTime * TICRATE / 8;
					break;
				case TIMEUNIT_TICS:
					holdTime = level.mapTime + newTime;
					break;
				case TIMEUNIT_SECS:
					holdTime = level.mapTime + newTime * TICRATE;
					break;
			}
		}
		else // Old InterpolationPoint class, always in octics
		{
			holdTime = level.mapTime + newTime * TICRATE / 8;
		}
	}

	//============================
	// SetInterpolationCoordinates
	//============================
	private void SetInterpolationCoordinates ()
	{
		bool changeAng = (args[ARG_OPTIONS] & OPTFLAG_ANGLE);
		bool changePi = (args[ARG_OPTIONS] & OPTFLAG_PITCH);
		bool changeRo = (args[ARG_OPTIONS] & OPTFLAG_ROLL);
		pPrev = pCurr = pNext = pNextNext = pos;
		pPrevAngs = pCurrAngs = pNextAngs = pNextNextAngs = (angle, pitch, roll);

		if (prevNode)
		{
			pPrev = pos + Vec3To(prevNode); //Make it portal aware
			if (changeAng) pPrevAngs.x = Normalize180(prevNode.angle);
			if (changePi) pPrevAngs.y = Normalize180(prevNode.pitch);
			if (changeRo) pPrevAngs.z = Normalize180(prevNode.roll);
		}

		if (currNode)
		{
			pCurr = pos + Vec3To(currNode); //Make it portal aware
			if (!prevNode)
			{
				if (changeAng) pCurrAngs.x = Normalize180(currNode.angle);
				if (changePi) pCurrAngs.y = Normalize180(currNode.pitch);
				if (changeRo) pCurrAngs.z = Normalize180(currNode.roll);
			}
			else
			{
				pCurrAngs = pPrevAngs + (
				changeAng ? DeltaAngle(pPrevAngs.x, currNode.angle) : 0,
				changePi  ? DeltaAngle(pPrevAngs.y, currNode.pitch) : 0,
				changeRo  ? DeltaAngle(pPrevAngs.z, currNode.roll)  : 0);
			}

			if (currNode.next)
			{
				pNext = pos + Vec3To(currNode.next); //Make it portal aware
				pNextAngs = pCurrAngs + (
				changeAng ? DeltaAngle(pCurrAngs.x, currNode.next.angle) : 0,
				changePi  ? DeltaAngle(pCurrAngs.y, currNode.next.pitch) : 0,
				changeRo  ? DeltaAngle(pCurrAngs.z, currNode.next.roll)  : 0);

				if (currNode.next.next)
				{
					pNextNext = pos + Vec3To(currNode.next.next); //Make it portal aware
					pNextNextAngs = pNextAngs + (
					changeAng ? DeltaAngle(pNextAngs.x, currNode.next.next.angle) : 0,
					changePi  ? DeltaAngle(pNextAngs.y, currNode.next.next.pitch) : 0,
					changeRo  ? DeltaAngle(pNextAngs.z, currNode.next.next.roll)  : 0);
				}
				else //No currNode.next.next
				{
					pNextNext = pNext;
					pNextNextAngs = pNextAngs;
				}
			}
			else //No currNode.next
			{
				pNextNext = pNext = pCurr;
				pNextNextAngs = pNextAngs = pCurrAngs;
			}
		}
		else //No currNode
		{
			pNextNext = pNext = pCurr;
			pNextNextAngs = pNextAngs = pCurrAngs;
		}

		if (!prevNode)
		{
			pPrev = pCurr;
			pPrevAngs = pCurrAngs;
		}
	}

	//============================
	// IsCarriable
	//============================
	static bool IsCarriable (Actor mo)
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
	// GetNewPassengers
	//============================
	private bool GetNewPassengers (bool ignoreObs)
	{
		//In addition to fetching passengers, this is where corpses get crushed, too. Items won't get destroyed.
		//Returns false if an actor is completely stuck inside platform unless 'ignoreObs' is true.

		double top = pos.z + height;
		Array<Actor> miscActors; //The actors on top of the passengers (We'll move those, too)
		Array<Actor> onTopOfMe;
		Array<FCW_Platform> otherPlats;

		//Call Grind() after we're done iterating because destroying
		//actors during iteration can mess up the iterator.
		Array<Actor> corpses;

		//Three things to do here when iterating:
		//1) Gather eligible passengers.
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
			bool oldPassenger = (passengers.Find(mo) < passengers.Size());
			if (mo is "FCW_Platform")
				otherPlats.Push(FCW_Platform(mo));

			//Check XY overlap
			double blockDist = radius + mo.radius;
			if (abs(it.position.x - mo.pos.x) < blockDist && abs(it.position.y - mo.pos.y) < blockDist)
			{
				//'ignoreObs' makes anything above our 'top' legit unless there's a 3D floor in the way.
				if (mo.pos.z >= top - TOPEPSILON && (ignoreObs || mo.pos.z <= top + TOPEPSILON) && //On top of us?
					mo.floorZ <= top + TOPEPSILON) //No 3D floor above our 'top' that's below 'mo'?
				{
					if (canCarry && !oldPassenger)
						onTopOfMe.Push(mo);
					continue;
				}

				if (OverlapZ(self, mo))
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
						if (!oldPassenger)
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
							if (!oldPassenger)
								onTopOfMe.Push(mo);
						}
					}
					continue;
				}
			}

			if (canCarry && !oldPassenger)
				miscActors.Push(mo); //We'll compare this later against the passengers
		}

		for (int i = 0; i < corpses.Size(); ++i)
			corpses[i].Grind(false);

		if (!onTopOfMe.Size() && !miscActors.Size())
			return true; //Found nothing new so stop here

		//Take into account the possibility that not all members
		//can be found in a blockmap search.
		if (group)
		for (int iPlat = 0; iPlat < group.members.Size(); ++iPlat)
		{
			let plat = group.GetMember(iPlat);
			if (plat && plat != self && otherPlats.Find(plat) >= otherPlats.Size())
				otherPlats.Push(plat);
		}

		for (int iPlat = 0; iPlat < otherPlats.Size(); ++iPlat)
		{
			let plat = otherPlats[iPlat];

			for (int i = 0; i < onTopOfMe.Size(); ++i)
			{
				let index = plat.passengers.Find(onTopOfMe[i]);
				if (index < plat.passengers.Size())
				{
					//Steal other platforms' passengers if
					//A) We don't share groups and our 'top' is higher or...
					//B) We don't share the "mirror" setting and the passenger's center is within our radius
					//and NOT within the other platform's radius.
					//(In other words, groupmates with the same "mirror" setting never steal each other's passengers.)
					bool stealPassenger;
					if (!group || group != plat.group)
						stealPassenger = (top > plat.pos.z + plat.height);
					else
						stealPassenger = (
							(args[ARG_OPTIONS] & OPTFLAG_MIRROR) != (plat.args[ARG_OPTIONS] & OPTFLAG_MIRROR) &&
							OverlapXY(self, onTopOfMe[i], radius) && !OverlapXY(plat, onTopOfMe[i], plat.radius) );

					if (stealPassenger)
						plat.passengers.Delete(index);
					else
						onTopOfMe.Delete(i--);
				}
			}
			for (int i = 0; i < miscActors.Size(); ++i)
			{
				if (plat.passengers.Find(miscActors[i]) < plat.passengers.Size())
					miscActors.Delete(i--);
			}
		}
		passengers.Append(onTopOfMe);

		//Now figure out which of the misc actors are on top of/stuck inside
		//established passengers.
		for (int i = 0; miscActors.Size() && i < passengers.Size(); ++i)
		{
			let mo = passengers[i];
			if (!mo)
			{
				passengers.Delete(i--);
				continue;
			}

			double moTop = mo.pos.z + mo.height;

			for (int iOther = 0; iOther < miscActors.Size(); ++iOther)
			{
				let otherMo = miscActors[iOther];

				if ( ( abs(otherMo.pos.z - moTop) <= TOPEPSILON || OverlapZ(mo, otherMo) ) && //Is 'otherMo' on top of 'mo' or stuck inside 'mo'?
					OverlapXY(mo, otherMo) ) //Within XY range?
				{
					miscActors.Delete(iOther--); //Don't compare this one against other passengers anymore
					passengers.Push(otherMo);
				}
			}
		}
		return true;
	}

	//============================
	// MovePassengers
	//============================
	private bool MovePassengers (bool teleMove)
	{
		//Returns false if a blocked passenger would block the platform's movement unless 'teleMove' is true

		if (!passengers.Size())
			return true; //No passengers? Nothing to do

		//The goal is to move all passengers as if they were one entity.
		//The only things that should block any of them are
		//non-passengers and geometry.
		//The exception is if a passenger can't fit at its new position
		//in which case it will be "solid" for the others.
		//
		//To accomplish this each of them will temporarily
		//be removed from the blockmap.

		int addToBmap = 0, removeFromBmap = 1;

		for (int i = 0; i < passengers.Size(); ++i)
		{
			let mo = passengers[i];
			if (mo && !mo.bNoBlockmap)
			{
				mo.A_ChangeLinkFlags(removeFromBmap);
			}
			else
			{
				passengers.Delete(i--);
				if (!passengers.Size())
					return true; //No passengers? Nothing to do
			}
		}

		//Move our passengers (platform rotation is taken into account)
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
		for (int i = 0; i < passengers.Size(); ++i)
		{
			let mo = passengers[i];
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
				{
					mo.SetOrigin(moNewPos, false);
					if (moNewPos.z != moOldPos.z)
						mo.CheckPortalTransition(); //Handle sector portals properly
				}
			}
			else
			{
				int maxSteps = 1;
				vector3 stepMove = level.Vec3Diff(moOldPos, moNewPos);

				//If the move is equal or larger than the passenger's radius
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
				//but the passenger should be treated like a flying object.
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

					//Take into account passengers getting Thing_Remove()'d
					//when they activate lines.
					if (!mo || mo.bDestroyed)
						break;

					if (stepMove.z)
						mo.CheckPortalTransition(); //Handle sector portals properly

					if (tryPos != mo.pos.xy && step < maxSteps-1)
					{
						//If 'mo' has passed through a portal then
						//adjust 'stepMove' if its angle changed.
						double angDiff = DeltaAngle(moOldAngle, mo.angle);
						if (angDiff)
							stepMove.xy = RotateVector(stepMove.xy, angDiff);
					}
				}

				//Take into account passengers getting Thing_Remove()'d
				//when they activate lines.
				if (!mo || mo.bDestroyed)
				{
					passengers.Delete(i--);
					continue;
				}
				mo.bNoDropoff = moOldNoDropoff;
			}

			if (moved)
			{
				//Only remember the old position if 'mo' was moved.
				//(Else we delete the 'passengers' entry containing 'mo', see below.)
				preMovePos.Push(moOldPos.x);
				preMovePos.Push(moOldPos.y);
				preMovePos.Push(moOldPos.z);
			}
			else
			{
				if (mo.pos != moOldPos)
					mo.SetOrigin(moOldPos, true);

				//This passenger will be 'solid' for the others
				mo.A_ChangeLinkFlags(addToBmap);
				passengers.Delete(i--);

				//See if it would block the platform
				bool blocked = ( !teleMove && CollisionFlagChecks(mo, self) &&
					OverlapZ(mo, self) && //Within Z range?
					OverlapXY(mo, self) && //Within XY range?
					mo.CanCollideWith(self, false) && self.CanCollideWith(mo, true) );

				//See if the ones we moved already will collide with this one
				//and if yes, move them back to their old positions.
				//(If the platform's "blocked" then move everyone back unconditionally.)
				for (int iOther = 0; iOther <= i; ++iOther)
				{
					let otherMo = passengers[iOther];
					if ( !blocked && ( !CollisionFlagChecks(otherMo, mo) ||
						!OverlapZ(otherMo, mo) || //Out of Z range?
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
					passengers.Delete(iOther--);
					i--;
				}

				if (blocked)
				{
					for (i = 0; i < passengers.Size(); ++i)
						passengers[i].A_ChangeLinkFlags(addToBmap); //Handle those that didn't get the chance to move
					PushObstacle(mo, level.Vec3Diff(oldPos, pos));
					return false;
				}
			}
		}

		//Anyone left in the 'passengers' array has moved successfully.
		//Change their angles.
		for (int i = 0; i < passengers.Size(); ++i)
		{
			let mo = passengers[i];
			mo.A_ChangeLinkFlags(addToBmap);
			if (delta)
				mo.angle = Normalize180(mo.angle + delta);
		}

		return true;
	}

	//============================
	// HandleOldPassengers
	//============================
	private void HandleOldPassengers ()
	{
		// Tracks established passengers and doesn't forget them even if
		// they're above our 'top' (with no 3D floors in between).
		// Such actors are mostly jumpy players and custom AI.
		//
		// Also keep non-flying monsters away from platform's edge.
		// Because the AI's native handling of trying not to
		// fall off of other actors just isn't good enough.

		double top = pos.z + height;
		for (int i = 0; i < passengers.Size(); ++i)
		{
			let mo = passengers[i];
			if (!mo || mo.bDestroyed || //Got Thing_Remove()'d?
				mo.bNoBlockmap || !IsCarriable(mo))
			{
				passengers.Delete(i--);
				continue;
			}

			//'floorZ' can be the top of a 3D floor that's right below an actor.
			//No 3D floors means 'floorZ' is the current sector's floor height.
			//(In other words 'floorZ' is not another actor's top that's below.)

			//Is 'mo' below our 'top'? Or is there a 3D floor above our 'top' that's also below 'mo'?
			if (mo.pos.z < top - TOPEPSILON || mo.floorZ > top + TOPEPSILON)
			{
				passengers.Delete(i--);
				continue;
			}

			if (!OverlapXY(self, mo)) //Is out of XY range?
			{
				passengers.Delete(i--);
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
			// are multiple passengers moving on the
			// same platform at the same time.
			//
			// Yes, this is a hack.

			mo.moveDir = int(mo.AngleTo(self) / 45) & 7;
			if (mo.moveCount < 1)
				mo.moveCount = 1;
		}
	}

	//============================
	// Lerp
	//============================
	private double Lerp (double p1, double p2)
	{
		return (p1 ~== p2) ? p1 : (p1 + time * (p2 - p1));
	}

	//============================
	// Splerp
	//============================
	private double Splerp (double p1, double p2, double p3, double p4)
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

		if (newPos.z != oldPos.z)
			CheckPortalTransition(); //Handle sector portals properly

		return true;
	}

	//============================
	// PlatMove
	//============================
	private bool PlatMove (vector3 newPos, double newAngle, double newPitch, double newRoll, bool teleMove)
	{
		if (pos == newPos && angle == newAngle && pitch == newPitch && roll == newRoll)
			return true;

		if (!GetNewPassengers(teleMove))
			return false;

		if (teleMove || pos == newPos)
		{
			oldPos = pos;
			oldAngle = angle;
			oldPitch = pitch;
			oldRoll = roll;

			if (pos != newPos)
			{
				SetOrigin(newPos, !teleMove);
				if (newPos.z != oldPos.z)
					CheckPortalTransition(); //Handle sector portals properly
			}
			angle = newAngle;
			pitch = newPitch;
			roll = newRoll;

			if (!MovePassengers(teleMove))
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
			bPlatInMove = true; //Temporarily don't clip against passengers
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

			if (!MovePassengers(false))
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
			newPos.x = Lerp(pCurr.x, pNext.x);
			newPos.y = Lerp(pCurr.y, pNext.y);
			newPos.z = Lerp(pCurr.z, pNext.z);
		}
		else //Spline
		{
			newPos.x = Splerp(pPrev.x, pCurr.x, pNext.x, pNextNext.x);
			newPos.y = Splerp(pPrev.y, pCurr.y, pNext.y, pNextNext.y);
			newPos.z = Splerp(pPrev.z, pCurr.z, pNext.z, pNextNext.z);
		}

		if (currNode && (args[ARG_OPTIONS] & OPTFLAG_FACEMOVE))
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
				newPos.x = Splerp(pPrev.x, pCurr.x, pNext.x, pNextNext.x);
				newPos.y = Splerp(pPrev.y, pCurr.y, pNext.y, pNextNext.y);
				newPos.z = Splerp(pPrev.z, pCurr.z, pNext.z, pNextNext.z);
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
			//Whether angle/pitch/roll interpolates or not is
			//determined in the interpolation coordinates.
			//That way the ACS functions aren't restricted
			//by the lack of OPTFLAG_ANGLE/PITCH/ROLL.
			if (args[ARG_OPTIONS] & OPTFLAG_LINEAR)
			{
				//Interpolate angle
				newAngle = Lerp(pCurrAngs.x, pNextAngs.x);

				//Interpolate pitch
				newPitch = Lerp(pCurrAngs.y, pNextAngs.y);

				//Interpolate roll
				newRoll = Lerp(pCurrAngs.z, pNextAngs.z);
			}
			else //Spline
			{
				//Interpolate angle
				newAngle = Splerp(pPrevAngs.x, pCurrAngs.x, pNextAngs.x, pNextNextAngs.x);

				//Interpolate pitch
				newPitch = Splerp(pPrevAngs.y, pCurrAngs.y, pNextAngs.y, pNextNextAngs.y);

				//Interpolate roll
				newRoll = Splerp(pPrevAngs.z, pCurrAngs.z, pNextAngs.z, pNextNextAngs.z);
			}
		}

		let oldPGroup = curSector.portalGroup;
		if (!PlatMove(newPos, newAngle, newPitch, newRoll, false))
			return false;

		if (curSector.portalGroup != oldPGroup) //Crossed a portal?
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

		for (int iPlat = 0; iPlat < group.members.Size(); ++iPlat)
		{
			let plat = group.GetMember(iPlat);
			if (!plat || plat == self)
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
				vector3 offset = level.Vec3Diff(pos, (spawnPoint.xy, spawnZ));
				newPos = level.Vec3Offset((plat.spawnPoint.xy, plat.spawnZ), offset);

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
					//'spawnAngle' is a uint16 but we need it
					//as a double to get the intended orbit result.
					double sAng = spawnAngle;
					cFirst = cos(-sAng); sFirst = sin(-sAng);
					cY = cos(delta);   sY = sin(delta);
					cP = cos(piDelta); sP = sin(piDelta);
					cR = cos(roDelta); sR = sin(roDelta);
					cLast = cos(sAng);   sLast = sin(sAng);
				}
				vector3 offset = level.Vec3Diff((spawnPoint.xy, spawnZ), (plat.spawnPoint.xy, plat.spawnZ));

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

				SetTimeFraction();
				time = 0;
				holdTime = 0;

				bPlatBlocked = false; //If IsBlocked() gets called in this tic, have it return false
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

		if (group)
		{
			if (group.members.Find(self) >= group.members.Size())
				group.members.Push(self); //Ensure we're in the group array

			if (!group.origin && bActive)
				group.origin = self;
		}

		if (!group || !group.origin)
		{
			HandleOldPassengers();
		}
		else if (group.origin == self)
		{
			for (int iPlat = 0; iPlat < group.members.Size(); ++iPlat)
			{
				let plat = group.GetMember(iPlat);
				if (plat)
					plat.HandleOldPassengers();
			}
		}

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
				SetHoldTime();
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
					SetTimeFraction();
				}

				if (!currNode || !currNode.next)
					Deactivate(self);
				else if (!(args[ARG_OPTIONS] & OPTFLAG_LINEAR) && !currNode.next.next)
					Deactivate(self);
			}
			break;
		}

		if (!group || !group.origin)
		{
			AdvanceStates();
		}
		else if (group.origin == self)
		{
			for (int iPlat = 0; iPlat < group.members.Size(); ++iPlat)
			{
				let plat = group.GetMember(iPlat);
				if (plat)
					plat.AdvanceStates();
			}
		}
	}

	//============================
	// AdvanceStates
	//============================
	private void AdvanceStates ()
	{
		if (!CheckNoDelay())
			return; //Freed itself (ie got destroyed)

		if (tics != -1 && --tics <= 0)
			SetState(curState.nextState);
	}

	//
	//
	// For scripting convenience with subclasses
	//
	//

	//============================
	// PlatHasMoved
	//============================
	bool PlatHasMoved ()
	{
		//When checking group members we only care about the origin.
		//Either "every member has moved" or "every member has not moved."
		let plat = self;
		if (group && group.origin)
			plat = group.origin;

		return (plat.pos != plat.oldPos ||
				plat.angle != plat.oldAngle ||
				plat.pitch != plat.oldPitch ||
				plat.roll != plat.oldRoll);
	}
	//============================
	// PlatIsActive
	//============================
	bool PlatIsActive ()
	{
		//When checking group members we only care about the origin.
		//Either "every member is active" or "every member is not active."
		let plat = self;
		if (group && group.origin)
			plat = group.origin;

		return plat.bActive;
	}

	//============================
	// PlatIsBlocked
	//============================
	bool PlatIsBlocked ()
	{
		//When checking group members we only care about the origin.
		//Either "every member is blocked" or "every member is not blocked."
		let plat = self;
		if (group && group.origin)
			plat = group.origin;

		return plat.bPlatBlocked;
	}

	//
	//
	// Everything below this point is ACS centric
	//
	//

	//============================
	// CommonACSSetup
	//============================
	private void CommonACSSetup (int travelTime)
	{
		currNode = null; //Deactivate when done moving
		prevNode = null;
		time = 0;
		holdTime = 0;
		timeFrac = 1.0 / max(1, travelTime); //Time unit is always in tics from the ACS side
		bActive = true;
		if (group) group.origin = self;
		bPlatBlocked = false; //If IsBlocked() gets called in this tic, have it return false
		pPrev = pCurr = pos;
		pPrevAngs = pCurrAngs = (
			Normalize180(angle),
			Normalize180(pitch),
			Normalize180(roll));
	}

	//============================
	// Move (ACS utility)
	//============================
	static void Move (int platTid, double offX, double offY, double offZ, int travelTime, double offAng = 0, double offPi = 0, double offRo = 0)
	{
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		FCW_Platform plat;
		while (plat = FCW_Platform(it.Next()))
		{
			plat.CommonACSSetup(travelTime);
			plat.pNext = plat.pNextNext = plat.Vec3Offset(offX, offY, offZ);
			plat.pNextAngs = plat.pNextNextAngs = plat.pCurrAngs + (offAng, offPi, offRo);
		}
	}

	//============================
	// MoveTo (ACS utility)
	//============================
	static void MoveTo (int platTid, double newX, double newY, double newZ, int travelTime, double offAng = 0, double offPi = 0, double offRo = 0)
	{
		//ACS itself has no 'vector3' variable type so it has to be 3 doubles (floats/fixed point numbers)
		vector3 newPos = (newX, newY, newZ);
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		FCW_Platform plat;
		while (plat = FCW_Platform(it.Next()))
		{
			plat.CommonACSSetup(travelTime);
			plat.pNext = plat.pNextNext = plat.pos + level.Vec3Diff(plat.pos, newPos); //Make it portal aware
			plat.pNextAngs = plat.pNextNextAngs = plat.pCurrAngs + (offAng, offPi, offRo);
		}
	}

	//============================
	// MoveToSpot (ACS utility)
	//============================
	static void MoveToSpot (int platTid, int spotTid, int travelTime, bool dontRotate = false)
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
			plat.CommonACSSetup(travelTime);
			plat.pNext = plat.pNextNext = plat.pos + plat.Vec3To(spot); //Make it portal aware
			plat.pNextAngs = plat.pNextNextAngs = plat.pCurrAngs + (
				!dontRotate ? DeltaAngle(plat.pCurrAngs.x, spot.angle) : 0,
				!dontRotate ? DeltaAngle(plat.pCurrAngs.y, spot.pitch) : 0,
				!dontRotate ? DeltaAngle(plat.pCurrAngs.z, spot.roll) : 0);
		}
	}

	//============================
	// HasMoved (ACS utility)
	//============================
	static bool HasMoved (int platTid)
	{
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		let plat = FCW_Platform(it.Next());
		return (plat && plat.PlatHasMoved());
	}

	//============================
	// IsActive (ACS utility)
	//============================
	static bool IsActive (int platTid)
	{
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		let plat = FCW_Platform(it.Next());
		return (plat && plat.PlatIsActive());
	}

	//============================
	// IsBlocked (ACS utility)
	//============================
	static bool IsBlocked (int platTid)
	{
		let it = level.CreateActorIterator(platTid, "FCW_Platform");
		let plat = FCW_Platform(it.Next());
		return (plat && plat.PlatIsBlocked());
	}
}

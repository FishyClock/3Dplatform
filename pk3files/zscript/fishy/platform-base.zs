/******************************************************************************

 3D platform actor class
 Copyright (C) 2022-2026 Fishytza A.K.A. FishyClockwork

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <https://www.gnu.org/licenses/>.

*******************************************************************************

 This is a script library containing a full-fledged, reasonably stable
 3D platform actor, a temporary answer to GZDoom/UZDoom's lack of "3D polyobjects".
 The platform can either be a sprite or a model.
 Though using models is the main point so it can masquerade as
 horizontally moving geometry that you can stand on and be carried by.

 In a nutshell this file contains:
 FishyPlatform - The main platform actor class;

 FishyPlatformNode - a platform-centric interpolation point actor class
 (though GZDoom/UZDoom's "InterpolationPoint" is still perfectly usable);

 FishyPlatformPivot - a special map spot (actor class) for any platform
 to rotate around just by changing its own yaw/pitch/roll.

 FishyDelayedAbort - a non-actor class that throws abort exceptions
 after an arbitrary delay.

 FishyPlatformGroup - a non-actor class to help with the "group" logic;

 And lastly
 FishyOldStuff_* - a measure that takes into account old
 "PathFollower" classes trying to use FishyPlatformNode
 as well as having a interpolation path made up of
 both InterpolationPoints and FishyPlatformNodes.

 It is recommended you replace the "Fishy" prefix to avoid conflicts with
 other people's projects.

 Regarding custom actors. Platforms can generally handle moving
 ordinary actors just fine, but if you have complex enemies/players/etc
 that are made up of multiple actors or otherwise need special treatment
 then please make use of the empty virtual functions:

 PassengerPreMove(Actor mo)
 PassengerPostMove(Actor mo, bool moved)
 SpecialBTIActor(Actor mo)

 PreMove is always called before the platform attempts to move the
 actor "mo" usually by calling TryMove().
 And PostMove is always called after "mo" was/wasn't moved.
 "moved" is set to "true" if "mo" was moved and "false" if it wasn't.

 SpecialBTIActor() is useful for actors detected during a BlockThingsIterator
 search. For cases where PassengerPre/PostMove() aren't good enough.

 There's another virtual function called GetCrushDamageSource(Actor dmgSrc)
 which can be used to determine crush damage damagetype as well as who
 gets blamed for causing the damage.

******************************************************************************/

class FishyPlatform : Actor abstract
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
		//$Arg0Tooltip Must be 'Platform Interpolation Point' or the old 'Interpolation Point' class.\nWhichever is more convenient.\n'Interpolation Special' works with both.\n\nNOTE: A negative 'Travel Time' is interpreted as speed in map units per tic.\n(This works on both interpolation point classes.)\n\nNOTE: If using interpolation point to determine angle/pitch/roll, (See "Options")\nthe related turn speed will be nullified while the platform is traveling (and not waiting)

		//$Arg1 Options
		//$Arg1Type 12
		//$Arg1Enum {1 = "Linear path <- Does nothing for non-origin group members"; 2 = "Use point angle (No angle turn speed!) <- ACS commands don't need this / Group move: Rotate angle"; 4 = "Use point pitch (No pitch turn speed!) <- ACS commands don't need this / Group move: Rotate pitch"; 8 = "Use point roll (No roll turn speed!) <- ACS commands don't need this / Group move: Rotate roll"; 16 = "Face movement direction (Needs 'Use point angle/pitch/roll' to work) <- Does nothing for non-origin group members"; 32 = "Don't clip against geometry and other platforms"; 64 = "Start active"; 128 = "Group move: Mirror group origin's movement"; 256 = "Add velocity to passengers when they jump away"; 512 = "Add velocity to passengers when stopping (and not blocked)"; 1024 = "Interpolation point is destination"; 2048 = "Resume path when activated again"; 4096 = "Always do 'crush damage' when pushing obstacles"; 8192 = "Pitch/roll changes don't affect passengers"; 16384 = "Passengers can push obstacles"; 32768 = "All passengers get temp NOBLOCKMAP'd before moving platform group <- Set on group origin"; 65536 = "When moving, allow walking monsters to cross onto other platforms and 'bridge' things"; 131072 = "Check for nearby things and line portals every tic";}
		//$Arg1Tooltip 'Group move' affects movement imposed by the group origin. (It only has an effect on non-origin group members.)\nThe 'group origin' is the platform that other members move with and rotate around.\nActivating any group member will turn it into the group origin.\nFlag 32768 is for cases where you want all passengers from the entire group to not collide with each other and to not collide with other platforms in the group (when moving everyone).

		//$Arg2 Platform(s) To Group With
		//$Arg2Type 14

		//$Arg3 Crush Damage
		//$Arg3Tooltip If an obstacle is pushed against a wall,\nthe damage is applied once per 4 tics.

		//$Arg4 Special Holder
		//$Arg4Type 14
		//$Arg4Tooltip Another actor that holds the thing action special and arguments for this platform.\n(The platform will copy the special+args for itself.)

		+INTERPOLATEANGLES;
		+ACTLIKEBRIDGE;
		+NOGRAVITY;
		+CANPASS;
		+SOLID;
		+SHOOTABLE; //Block hitscan attacks
		+BUMPSPECIAL;

		//These are needed because we're shootable
		+NODAMAGE;
		+NOBLOOD;
		+DONTTHRUST;
		+NOTAUTOAIMED;

		FishyPlatform.AirFriction 0.99;
	}

	//===New flags===//
	int platFlags;
	flagdef Carriable: platFlags, 0; //Let's this platform be carried (like a passenger) by other platforms
	flagdef UseActorTick: platFlags, 1; //If we're not in a group, call Actor.Tick() in our Tick() override to handle world interaction
	flagdef NoPassOrbit: platFlags, 2; //Passengers are unaffected by platform angle/pitch/roll changes
	flagdef NoCorpseGib: platFlags, 3; //Don't gib corpses when touching them

	//===New properties===//
	double platAirFric; //For platforms that have +PUSHABLE and +NOGRAVITY. (The pre-existing 'friction' property + sector friction are for gravity bound pushables instead.)
	property AirFriction: platAirFric;

	//===User variables===//
	//$UserDefaultValue true
	bool user_scalesize; //If true, the radius and height will be affected by its scale values

	string user_snd_start; //NOTE: Variable type must be "string", not "sound" or UDB won't recognize them
	string user_snd_stop;
	string user_snd_blocked;
	string user_snd_move;
	bool user_snd_movestopsstart;
	int user_snd_delaytomove; //If 0, wait until 'snd_start' is done

	// If following interpolation point path (and not waiting due to "hold time"), use "onpath" speeds.
	// NOTE: If using interpolation point to set angle/pitch/roll, then the related "onpath" speed is nullified! (No turning)
	// NOTE: If using ACS to give explicit rotations on angle/pitch/roll, then the related "onpath" speed is nullified! (No turning)
	//
	// Otherwise, if moving with velocity, use "withvel" speeds.
	// Otherwise, use "idle" speeds.
	// So in short the priority is: "onpath" > "withvel" > "idle"
	//
	// NOTE: turn speeds have no effect on group members who aren't the origin.
	// If a group starts with no origin then the first platform with any "idle" speeds
	// becomes the origin (just because it starts turning/moving)
	//
	double user_turnspeed_angle_onpath;
	double user_turnspeed_angle_withvel;
	double user_turnspeed_angle_idle;
	double user_turnspeed_pitch_onpath;
	double user_turnspeed_pitch_withvel;
	double user_turnspeed_pitch_idle;
	double user_turnspeed_roll_onpath;
	double user_turnspeed_roll_withvel;
	double user_turnspeed_roll_idle;
}

class FishyPlatformNode : InterpolationPoint
{
	//===User variables===//
	bool user_nopositionchange; //If true, only use point to adjust angle/pitch/roll, NOT as travel destination
	bool user_ignoreaxis_x; //If true, platform will ignore point's X pos
	bool user_ignoreaxis_y; //If true, platform will ignore point's Y pos
	bool user_ignoreaxis_z; //If true, platform will ignore point's Z pos
	bool user_ignorepivot; //If true and this point is the destination, platform will not rotate around its pivot
	bool user_undopivotadjustment; //If true, when this point is the platform's destination, reset the platform's offseted travel pos (if any)

	// Path following and pivot behavior can coexist.
	//
	// Pivot behavior: Platform position changes by rotating
	// around its pivot due to angle/pitch/roll adjustments.
	// This affects the travel path, and the adjusted
	// position persists even if rotation stops.
	//
	// NOTE: Variables ignoring position changes (e.g. 
	// user_ignoreaxis_x) only affect path following, NOT
	// pivot-related position changes.
	//
	// To ensure the platform moves to this point's exact
	// position ignoring prior pivot adjustments (assuming
	// no angle changes, or 'user_ignorepivot' was true), set
	// 'user_undopivotadjustment' to true.

	Default
	{
		//$Title Platform Interpolation Point

		//$Arg0 Next Point
		//$Arg0Type 14
		//$Arg0Tooltip Next point must be another platform interpolation point.\n(It can't be the old interpolation point class.)\nNOTE: Check the 'Custom' tab for more options.

		//$Arg1 Travel Time
		//$Arg1Tooltip A negative 'Travel Time' is interpreted as speed in map units per tic. (Even on old interpolation points.)\nNOTE: Check the 'Custom' tab for more options.

		//$Arg2 Hold Time

		//$Arg3 Travel Time Unit
		//$Arg3Type 11
		//$Arg3Enum {0 = "Octics"; 1 = "Tics"; 2 = "Seconds";}
		//$Arg3Tooltip Does nothing if 'Travel Time' is negative.\nNOTE: Check the 'Custom' tab for more options.

		//$Arg4 Hold Time Unit
		//$Arg4Type 11
		//$Arg4Enum {0 = "Octics"; 1 = "Tics"; 2 = "Seconds";}
	}
}

class FishyPlatformPivot : Actor
{
	Default
	{
		//$Title Platform Pivot
		//$Sprite pivot0
		//$NotAngled

		//$Arg0 Platform(s)
		//$Arg0Type 14
		//$Arg0Tooltip Platform(s) whose pivot to become.\n\nNOTE: Any platform that activates this thing will be affected as well.\n\nTip: one way a platform can activate a pivot thing is by using a Interpolation Special.

		//$Arg1 Needs Activation
		//$Arg1Type 11
		//$Arg1Enum {0 = "No"; 1 = "Yes";}
		//$Arg1Tooltip Must be activated before setting the pivot data for the platform(s)?

		//$Arg2 Attached Pivot
		//$Arg2Type 11
		//$Arg2Enum {0 = "No"; 1 = "Yes";}
		//$Arg2Default 1
		//$Arg2Tooltip An attached pivot follows the platform around\nwhile an unattached pivot is a constant point on the map.\n\nNOTE: This 'constant point' gets shifted when the platform crosses a portal,\nincluding non-static portals.\n\nNOTE: The pivot data is set internally for each platform.\nJust moving this spot around will NOT affect the platform's pivot data!

		+NOINTERACTION;
		+NOBLOCKMAP;
		+NOSECTOR;
	}
}

//Ultimate Doom Builder doesn't need to read the rest
//$GZDB_SKIP

extend class FishyPlatformNode
{
	void PNodeFormChain ()
	{
		// The relevant differences from InterpolationPoint's FormChain() are:
		// 1) The archaic tid/hi-tid lookup is gone.
		// 2) The tid to look for is on a different argument.
		// 3) The pitch isn't clamped.

		for (InterpolationPoint node = self; node; node = node.next)
		{
			if (node.bVisited)
				return;
			node.bVisited = true;

			let it = level.CreateActorIterator(node.args[0], "InterpolationPoint");
			do
			{
				node.next = InterpolationPoint(it.Next());
			} while (node.next == node); //Don't link to self

			if (!node.next && node.args[0])
			{
				Console.Printf("\n\ckPlatform interpolation point with tid " .. node.tid .. " at position " ..node.pos ..
				":\n\ckcannot find next platform interpolation point with tid " .. node.args[0] .. ".");
			}
			else if (node.next && !(node.next is "FishyPlatformNode"))
			{
				Console.Printf("\ckPlatform interpolation point with tid " .. node.tid .. " at position " ..node.pos ..
				":\n\ckis pointing at a non-platform interpolation point with tid " .. node.args[0] .. " at position " .. node.next.pos .. "\n.");
				FishyDelayedAbort.Create(TICRATE, FishyDelayedAbort.INTERPOLATIONPOINT_ERROR);
				return;
			}
		}
	}

	vector3 FilterNoPosChange (vector3 noChange, vector3 yesChange)
	{
		vector3 result = yesChange;

		if (user_ignoreaxis_x || user_nopositionchange)
			result.x = noChange.x;
		if (user_ignoreaxis_y || user_nopositionchange)
			result.y = noChange.y;
		if (user_ignoreaxis_z || user_nopositionchange)
			result.z = noChange.z;

		return result;
	}

	bool HasNoPosChange ()
	{
		return (user_nopositionchange ||
			(user_ignoreaxis_x && user_ignoreaxis_y && user_ignoreaxis_z)
		);
	}
}

extend class FishyPlatformPivot
{
	enum ArgValues
	{
		PIVOTARG_PLAT		= 0,
		PIVOTARG_NEEDSACT	= 1,
		PIVOTARG_ATTACH		= 2,
	};

	override void BeginPlay ()
	{
		ChangeStatNum(FishyPlatform.STAT_FPLAT - 1); //Our PostBeginPlay() must run before any platform's PostBeginPlay()

		//NOTE TO SELF: Setting the statnum to a non-thinker makes it not call PostBeginPlay() so let's not do that
	}

	override void PostBeginPlay ()
	{
		if (!args[PIVOTARG_NEEDSACT])
			Activate(null);
	}

	override void Activate (Actor activator)
	{
		let plat = FishyPlatform(activator);
		if (plat)
			plat.SetPivot(pos, args[PIVOTARG_ATTACH]);

		if (args[PIVOTARG_PLAT])
		{
			bool foundOne = false;
			let it = level.CreateActorIterator(args[PIVOTARG_PLAT], "FishyPlatform");
			while (plat = FishyPlatform(it.Next()))
			{
				plat.SetPivot(pos, args[PIVOTARG_ATTACH]);
				foundOne = true;
			}
			if (!foundOne)
				Console.Printf("\ckPivot spot with tid " .. tid .. " at position " .. pos ..
					"\n\ckcan't find any platform with tid " .. args[PIVOTARG_PLAT]);
		}
	}

	override void Tick ()
	{
	}
}

//I needed something that would issue the fatal error message after
//flooding the console with problematic map setups that cannot
//or should not be ignored. Like mixing up the old and new
//interpolation points. Or in the case of the generic subclass,
//declaring an invalid model which can't be read to set the
//collision size. (See platform-generic.zs)
class FishyDelayedAbort : Thinker
{
	const INTERPOLATIONPOINT_ERROR = "Path followers, moving cameras, and actor movers are not meant to use 'Platform Interpolation Points'." ..
		"\nPlease use the old 'Interpolation Point' instead." ..
		"\n\nLikewise, the old 'Interpolation Point' should not point to a 'Platform Interpolation Point' nor vice-versa.\n.";

	int abortTime;
	string message;

	static void Create (int delay, string theProblem)
	{
		let delayedAbort = new("FishyDelayedAbort");
		delayedAbort.abortTime = level.mapTime + delay;
		delayedAbort.message = theProblem;
	}

	override void Tick ()
	{
		if (level.mapTime >= abortTime)
			ThrowAbortException(message);
	}
}

//A container class for grouped platforms.
//It has an array pointing to all group members and each member points to this group.
class FishyPlatformGroup play
{
	Array<FishyPlatform> members;
	FishyPlatform origin;	//The member that thinks for the other members when it ticks.
	FishyPlatform carrier;	//A non-member that carries one member of this group. Used for passenger theft checks.
	transient int lastZFixTime; //Keep the Z fixing once per tic when doing whole groups. See DoPlatZFix().

	static FishyPlatformGroup Create ()
	{
		let group = new("FishyPlatformGroup");
		group.lastZFixTime = -1;
		return group;
	}

	void Add (FishyPlatform plat)
	{
		plat.group = self;
		if (members.Find(plat) >= members.Size())
			members.Push(plat);
	}

	FishyPlatform GetMember (int index)
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

	void MergeWith (FishyPlatformGroup otherGroup)
	{
		for (int i = 0; i < otherGroup.members.Size(); ++i)
		{
			let plat = otherGroup.GetMember(i);
			if (plat)
				Add(plat);
		}

		if (!carrier && otherGroup.carrier)
			carrier = otherGroup.carrier;
	}
}

extend class FishyPlatform
{
	enum ArgValues
	{
		ARG_NODETID			= 0,
		ARG_OPTIONS			= 1,
		ARG_GROUPTID		= 2,
		ARG_CRUSHDMG		= 3,
		ARG_SPECTID			= 4,

		//For "ARG_OPTIONS"
		OPTFLAG_LINEAR			= 1,
		OPTFLAG_ANGLE			= (1<<1),
		OPTFLAG_PITCH			= (1<<2),
		OPTFLAG_ROLL			= (1<<3),
		OPTFLAG_FACEMOVE		= (1<<4),
		OPTFLAG_IGNOREGEO		= (1<<5),
		OPTFLAG_STARTACTIVE		= (1<<6),
		OPTFLAG_MIRROR			= (1<<7),
		OPTFLAG_ADDVELJUMP		= (1<<8),
		OPTFLAG_ADDVELSTOP		= (1<<9),
		OPTFLAG_GOTONODE		= (1<<10),
		OPTFLAG_RESUMEPATH		= (1<<11),
		OPTFLAG_HURTFULPUSH		= (1<<12),
		OPTFLAG_NOPITCHROLL		= (1<<13),
		OPTFLAG_PASSCANPUSH		= (1<<14),
		OPTFLAG_DIFFPASSCOLL	= (1<<15),
		OPTFLAG_PASSCANCROSS	= (1<<16),
		OPTFLAG_REALTIMEBMAP	= (1<<17),

		//FishyPlatformNode args that we check
		NODEARG_TRAVELTIME		= 1, //Also applies to InterpolationPoint
		NODEARG_HOLDTIME		= 2, //Ditto
		NODEARG_TRAVELTUNIT		= 3,
		NODEARG_HOLDTUNIT		= 4,

		//For FishyPlatformNode's "NODEARG_TRAVELTUNIT" and "NODEARG_HOLDTUNIT"
		TIMEUNIT_OCTICS		= 0,
		TIMEUNIT_TICS		= 1,
		TIMEUNIT_SECS		= 2,
	};

	//For PlatMove()
	enum PMoveTypes
	{
		MOVE_NORMAL =		0,
		MOVE_TELEPORT =		1,
		MOVE_TRUETELE =		2, //Like MOVE_TELEPORT but calls Teleport() instead of SetOrigin()
		MOVE_REPEAT =		3, //Combines aspects of MOVE_NORMAL and MOVE_QUICK
		MOVE_QUICK =		-1,
		MOVE_QUICKTELE =	-2,
	};

	const STAT_FPLAT = STAT_SECTOREFFECT + 1; //Platforms tick after sector thinkers - and pivot spots tick before platforms
	const TOP_EPSILON = 1.0; //For Z checks (if something is on top of something else)
	const YES_BMAP = 0; //For A_ChangeLinkFlags()
	const NO_BMAP = 1;
	const EXTRA_SIZE = 20; //For line collision checking (when looking for unlinked line portals)
	const INTERNALFLAG_ACSMOVE = 1; //When reaching destination, disregard any set nodes and pretend we're finished
	const BMAP_SEARCH_INTERVAL = 35; //See GetNewBmapResults() for comments about this
	const BMAP_RADIUS_MULTIPLIER = 2; //Ditto
	const CHAN_USERSND = 50; //Sound channel for user var sounds
	const MISCUSERVAR_LOWVEL = 0.1; //For user var sounds and turn speeds, we're "not moving" if velocity square length is below this

	vector3 oldPos;
	double oldAngle;
	double oldPitch;
	double oldRoll;
	FishyPlatformGroup group;
	vector3 groupMirrorPos; //The position when this platform joins a group - used for mirroring behaviour - changes when origin changes.
	vector3 groupRotPos;  //The position when this platform joins a group - used for rotation behaviour - doesn't change when origin changes.
	double groupAngle; //The angle when this platform joins a group - doesn't change when origin changes.
	double groupPitch; //The pitch when this platform joins a group - doesn't change when origin changes.
	double groupRoll;  //The roll when this platform joins a group - doesn't change when origin changes.
	vector3 groupRotOffset;  //Precalculated offset from origin's groupRotPos to rotator's groupRotPos - changes when origin changes.
	quat groupRotAngDiff; //Precalculated deltas from origin's groupAngle/Pitch/Roll to rotator's groupAngle/Pitch/Roll as a quaternion - changes when origin changes.
	bool bQuatAngsAtPole; //Only relevant when our yaw, pitch and roll were converted from a quat.
	double time;
	double reachedTime;
	double timeFrac;
	int holdTime;
	bool bFollowingPath;
	int startSoundTime;
	bool bUserSoundsWasMoving;
	transient bool bUserSoundsShouldMove;
	transient bool bUserSoundsHasMoved;
	transient bool bRanActivationRoutine; //Used to check if SetInterpolationCoordinates() or "resume path" Activate() was called on self through CallNodeSpecials().
	transient bool bRanACSSetupRoutine; //Used to check if CommonACSSetup() was called on self through CallNodeSpecials().
	transient bool bTimeAlreadySet; //Used to check if 'time' was set on self through CallNodeSpecials().
	transient bool bInMove; //No collision between a platform and its passengers during said platform's move.
	transient bool bMoved; //Used for PassengerPostMove() when everyone has finished (or tried) moving in this tic.
	bool bInterpolateSuccess; //Don't run HandleNonPathTurnSpeeds() if any Interpolate() call was successful in the last tic.
	InterpolationPoint currNode, firstNode;
	InterpolationPoint prevNode, firstPrevNode;
	bool bGoToNode;
	Array<Actor> nearbyActors; //The actors detected in the last blockmap search
	Array<Line> nearbyUPorts; //The unlinked line portals detected in the last blockmap search
	int noBmapSearchTics;
	vector2 oldBmapSearchPos;
	Array<Actor> passengers;
	Array<Actor> stuckActors;
	bool bPushStuckActors; //Do not push away stuck actors until we try moving for the first time
	Line lastUPort;
	private FishyPlatform portTwin; //Helps with collision when dealing with unlinked line portals
	private bool bPortCopy;
	private bool bSearchForUPorts;
	double portDelta;
	int acsFlags;
	transient int lastGetNPTime; //Make sure GetNewPassengers() doesn't run its routine more than once per tic
	transient bool lastGetNPResult;
	transient int lastGetUPTime; //Same deal for GetUnlinkedPortal()
	transient int lastGetBmapTime; //Same deal for GetNewBmapResults()
	transient bool bPlatPorted; //Set by PostTeleport() and checked by various routines (The pre-existing 'bTeleport' flag isn't good enough)
	transient int platTeleFlags; //Ditto
	int options;
	int crushDamage;

	//Unlike PathFollower classes, our interpolations are done with
	//vector3 coordinates instead of checking InterpolationPoint positions.
	//This is done for 3 reasons:
	//1) Making it portal aware.
	//2) Can be arbitrarily set through ACS (See utility functions below).
	//3) If following a path, can course correct itself after being pushed or carried by another platform.
	vector3 pCurr, pPrev, pNext, pLast; //Positions in the world.
	vector3 pCurrAngs, pPrevAngs, pNextAngs, pLastAngs; //X = angle, Y = pitch, Z = roll.

	//The pivot behavior is tied with the path following behavior
	vector3 interpolatedPivotOffset;
	vector3 pivotVector;
	bool bPivotVectorIsPosition; //Otherwise it's an offset
	bool bIgnorePivot;

	//============================
	// BeginPlay (override)
	//============================
	override void BeginPlay ()
	{
		// Change the statnum so that platforms tick
		// after every door/crusher/lift etc has ticked.
		// Please note that this has the subtle side effect of
		// also ticking after every non-platform actor
		// has ticked.
		//
		// Changing the statnum along with calling FindFloorCeiling()
		// in the CheckFloorCeiling() function is a workaround to
		// make a platform move with a ceiling/3D floor that's pushing it up/down
		// and not clip through it as the ceiling/3D floor moves.
		// If we don't change the statnum then a platform being pushed up/down
		// would appear to be partially stuck inside the ceiling/3D floor
		// as it moves.
		//
		// Feel free to comment-out or remove this if it's causing
		// problems for you and you don't have platforms that get
		// in the way of moving ceilings or 3D floors.
		ChangeStatNum(STAT_FPLAT); //This is STAT_SECTOREFFECT + 1

		oldPos = pos;
		oldAngle = angle;
		oldPitch = pitch;
		oldRoll = roll;
		groupMirrorPos = pos;
		groupRotPos = pos;
		groupAngle = angle;
		groupPitch = pitch;
		groupRoll = roll;
		time = 1.1;
		lastGetNPTime = -1;
		lastGetUPTime = -1;
		lastGetBmapTime = -1;
		options = -1;
		crushDamage = -1;
		pCurr.x = double.nan;

		// Normally, I would set atypical default values for user variables here
		// because BeginPlay() runs before the values from the UDMF side are actually set.
		// And if a user variable was implemented after a thing was placed in
		// some old map, the UDMF version doesn't exist.
		// Meaning whatever you set in BeginPlay() is unchanged.
		//
		// In this case the default value for 'user_scalesize' should be 'true'.
		// But this is deliberately NOT set here so platforms in old maps
		// do not scale their radius and height.
		//
		// However, from now on placing a platform in the map will have
		// 'user_scalesize' set to 'true' by default.
	}

	//============================
	// PostBeginPlay (override)
	//============================
	override void PostBeginPlay ()
	{
		if (bPortCopy)
		{
			Super.PostBeginPlay();
			return;
		}

		//Only do BlockLinesIterator searches if there are unlinked line portals on the map
		for (uint iPorts = level.linePortals.Size(); iPorts-- > 0;)
		{
			let port = level.linePortals[iPorts];
			if (port.mType == LinePortal.PORTT_TELEPORT || port.mType == LinePortal.PORTT_INTERACTIVE)
			{
				bSearchForUPorts = true;
				break;
			}
		}

		//Setting the scale through UDB affects collision size
		if (user_scalesize)
			A_SetSize(radius * abs(scale.x), height * abs(scale.y));

		if (options == -1) //Not already set through ACS?
			options = args[ARG_OPTIONS];
		if (crushDamage == -1) //Ditto
			crushDamage = args[ARG_CRUSHDMG];

		//In case the mapper placed walking monsters on an idle platform
		//get something for HandleOldPassengers() to monitor.
		GetNewBmapResults();
		GetNewPassengers(true);

		bool noPrefix = (args[ARG_GROUPTID] && !SetUpGroup(args[ARG_GROUPTID], false));

		//Having a group origin at this point implies the group is already on the move.
		//We need to call PlatMove() on the origin here to move us along with the rest
		//of the group. This matters if the origin's first interpolation point has a
		//defined hold time because depending on who ticks first some members might have
		//already moved and some might have not.
		if (group && group.origin)
		{
			let ori = group.origin;
			if (!(options & OPTFLAG_MIRROR))
				SetGroupRotationInfo();
			ori.PlatMove(ori.pos, ori.angle, ori.pitch, ori.roll, MOVE_TELEPORT);
		}
		else if (group && !group.origin)
		{
			//Same issue if we're grouping with a lone, active platform.
			//Make it the origin and call PlatMove() for the same reason.
			for (int i = 0; i < group.members.Size(); ++i)
			{
				let plat = group.GetMember(i);
				if (plat && (plat.bFollowingPath || plat.vel != (0, 0, 0)))
				{
					SetGroupOrigin(plat, false);
					plat.PlatMove(plat.pos, plat.angle, plat.pitch, plat.roll, MOVE_TELEPORT);
					break;
				}
			}
		}

		//We use our thing arguments to define our behaviour.
		//Our actual thing special and arguments have to be defined in another actor (eg. a Mapspot).
		int nodeTid = args[ARG_NODETID]; //Need this for later.
		if (args[ARG_SPECTID])
		{
			let it = level.CreateActorIterator(args[ARG_SPECTID]);
			Actor mo = it.Next();
			if (mo == self)
				mo = it.Next(); //Ignore self

			if (mo)
			{
				special = mo.special;
				for (int i = 0; i < 5; ++i)
					args[i] = mo.args[i];
			}
			else
			{
				String prefix = noPrefix ? "" : "\n\ckPlatform class '" .. GetClassName() .. "' with tid " .. tid .. " at position " .. pos .. ":\n";
				Console.Printf(prefix .. "\ckCan't find special holder with tid " .. args[ARG_SPECTID] .. ".");
				noPrefix = true;
			}
		}

		//Print no (additional) warnings if we're not supposed to have a interpolation point
		if (nodeTid && SetUpPath(nodeTid, noPrefix) && (options & OPTFLAG_STARTACTIVE))
			Activate(self);

		Super.PostBeginPlay();
	}

	//============================
	// IsPortalCopy
	//============================
	bool IsPortalCopy ()
	{
		//A getter function that's mostly useful for subclasses.
		//I want 'bPortCopy' to stay private.
		return bPortCopy;
	}

	//============================
	// SetUpPath
	//============================
	private bool SetUpPath (int nodeTid, bool noPrefix)
	{
		String prefix = noPrefix ? "" : "\n\ckPlatform class '" .. GetClassName() .. "' with tid " .. tid .. " at position " .. pos .. ":\n";
		let it = level.CreateActorIterator(nodeTid, "InterpolationPoint");
		firstNode = InterpolationPoint(it.Next());
		if (!firstNode)
		{
			Console.Printf(prefix .. "\ckCan't find interpolation point with tid " .. nodeTid .. ".");
			return false;
		}

		//Verify the path has enough nodes
		if (firstNode is "FishyPlatformNode")
		{
			FishyPlatformNode(firstNode).PNodeFormChain();
		}
		else
		{
			firstNode.FormChain();
			FishyOldStuff_Common.CheckNodeTypes(firstNode); //The old nodes shouldn't point to platform nodes
		}

		bool optGoToNode = (options & OPTFLAG_GOTONODE);
		bool optLinear = (options & OPTFLAG_LINEAR);

		if (optLinear)
		{
			//Linear path; need 2 nodes unless the first node is the destination
			if (!optGoToNode && !firstNode.next)
			{
				Console.Printf(prefix .. "\ckLinear path needs at least 2 nodes. (Interpolation point tid: " .. nodeTid .. ".)");
				return false;
			}
		}
		else //Spline path; need 4 nodes unless the first node is the destination
		{
			if (!optGoToNode && (
				!firstNode.next ||
				!firstNode.next.next ||
				!firstNode.next.next.next) )
			{
				Console.Printf(prefix .. "\ckSpline path needs at least 4 nodes. (Interpolation point tid: " .. nodeTid .. ".)");
				return false;
			}
		}

		//Check if the path loops
		let node = firstNode;
		Array<InterpolationPoint> checkedNodes;
		while (node.next && node.next != firstNode && checkedNodes.Find(node) >= checkedNodes.Size())
		{
			checkedNodes.Push(node);
			node = node.next;
		}

		if (node.next == firstNode)
		{
			firstPrevNode = node; //The path loops back to our first node
		}
		else if (!optGoToNode && !optLinear)
		{
			//Non-looping spline path and the
			//first node is not the destination.
			//
			//Spline paths need to start at the
			//second node.
			firstPrevNode = firstNode;
			firstNode = firstNode.next;
		}
		else
		{
			//Non-looping linear path or the
			//first node is the destination.
			firstPrevNode = null;
		}

		if (!bFollowingPath)
		{
			//For ACSFuncNextNode() and ACSFuncPrevNode()
			currNode = firstNode;
			prevNode = firstPrevNode;
			bGoToNode = optGoToNode;
		}
		return true;
	}

	//============================
	// SetUpGroup
	//============================
	private bool SetUpGroup (int otherPlatTid, bool doUpdateGroupInfo)
	{
		let it = level.CreateActorIterator(otherPlatTid, "FishyPlatform");
		FishyPlatform plat;
		Array<FishyPlatform> newMembers;
		bool foundOne = false;
		bool gotOrigin = (group && group.origin);

		while (plat = FishyPlatform(it.Next()))
		{
			if (plat != self)
			{
				foundOne = true;

				//We have to check for these conditions in here, too
				//because this platform might have not called PostBeginPlay() yet.
				//(This is done because 'options' can be checked prematurely.)
				if (plat.options == -1) //Not already set through ACS?
					plat.options = plat.args[ARG_OPTIONS];
				if (plat.crushDamage == -1) //Ditto
					plat.crushDamage = plat.args[ARG_CRUSHDMG];
			}

			if (plat.group) //Target is in its own group?
			{
				gotOrigin |= (plat.group.origin != null);
				if (!group) //We don't have a group?
				{
					if (doUpdateGroupInfo && gotOrigin)
						newMembers.Push(self);
					plat.group.Add(self);
				}
				else if (plat.group != group) //Both are in different groups?
				{
					//Depending on who has an origin the other group's
					//members will have to have their group info updated.
					//If both have an origin then our group's origin
					//overrides the other detected group's origin by default.
					let group1 = group.origin ? group : plat.group;
					let group2 = group.origin ? plat.group : group;

					if (doUpdateGroupInfo && gotOrigin)
						newMembers.Append(group2.members);
					group1.MergeWith(group2);
				}
				//else - nothing happens because it's the same group or plat == self
			}
			else if (group) //We're in a group but target doesn't have a group?
			{
				if (doUpdateGroupInfo && gotOrigin)
					newMembers.Push(plat);
				group.Add(plat);
			}
			else if (plat != self) //Neither are in a group
			{
				let newGroup = FishyPlatformGroup.Create();
				newGroup.Add(self);
				newGroup.Add(plat);
			}
		}

		if (!foundOne)
		{
			Console.Printf("\n\ckPlatform class '" .. GetClassName() .. "' with tid " .. tid .. " at position " .. pos ..
				":\n\ckCan't find platform(s) with tid " .. otherPlatTid .. " to group with.");
			return false;
		}

		if (!doUpdateGroupInfo)
			return true;

		if (!gotOrigin)
		for (int i = 0; i < group.members.Size(); ++i)
		{
			//With no designated origin, just update everyone's
			//group info to where they are.
			plat = group.GetMember(i);
			if (plat)
			{
				plat.groupMirrorPos = plat.pos;
				plat.groupRotPos = plat.pos;
				plat.groupAngle = plat.angle;
				plat.groupPitch = plat.pitch;
				plat.groupRoll = plat.roll;
			}
		}
		else
		{
			//Only set up the new members' group info relative
			//to the origin.
			for (uint i = newMembers.Size(); i-- > 0;)
			{
				plat = newMembers[i];
				if (plat)
					plat.UpdateGroupInfo();
			}
		}
		return true;
	}

	//============================
	// SetGroupRotationInfo
	//============================
	private void SetGroupRotationInfo ()
	{
		let ori = group.origin;

		quat q = quat.FromAngles(ori.groupAngle, ori.groupPitch, ori.groupRoll);
		q = q.Inverse(); //Declaring "quat.FromAngles(bla, bla, bla).Inverse();" gives me a startup error

		groupRotOffset = q * level.Vec3Diff(ori.groupRotPos, groupRotPos);
		groupRotAngDiff = q * quat.FromAngles(groupAngle, groupPitch, groupRoll);
		bQuatAngsAtPole = false;
	}

	//============================
	// SetGroupOrigin
	//============================
	private void SetGroupOrigin (FishyPlatform ori, bool setMirrorPos = true, bool setNonOriginNoFollow = false)
	{
		group.origin = ori;
		for (int i = 0; i < group.members.Size(); ++i)
		{
			let plat = group.GetMember(i);
			if (plat)
			{
				if (setMirrorPos)
					plat.groupMirrorPos = plat.pos;

				if (plat != group.origin)
				{
					if (!(plat.options & OPTFLAG_MIRROR))
						plat.SetGroupRotationInfo();
					if (setNonOriginNoFollow)
						plat.bFollowingPath = false;
				}
			}
		}
	}

	//============================
	// UpdateGroupInfo
	//============================
	private void UpdateGroupInfo ()
	{
		//Called when a platform joins a group with a designated
		//origin. Or when a group member's mirror flag changes.

		let ori = group.origin;

		if (options & OPTFLAG_MIRROR)
		{
			double delta = DeltaAngle(ori.angle, ori.groupAngle);
			double piDelta = DeltaAngle(ori.pitch, ori.groupPitch);
			double roDelta = DeltaAngle(ori.roll, ori.groupRoll);
			vector3 offset = level.Vec3Diff(ori.groupMirrorPos, ori.pos);

			groupMirrorPos = level.Vec3Offset(pos, offset);
			groupAngle = angle - delta;
			groupPitch = pitch - piDelta;
			groupRoll = roll - roDelta;
		}
		else //Set up for proper rotation
		{
			quat qOriAngsInv = quat.FromAngles(ori.angle, ori.pitch, ori.roll);
			qOriAngsInv = qOriAngsInv.Inverse(); //Declaring "quat.FromAngles(bla, bla, bla).Inverse();" gives me a startup error
			quat qOriGrpAngs = quat.FromAngles(ori.groupAngle, ori.groupPitch, ori.groupRoll);

			//Compute the position offsets and save into 'groupRotPos' so SetGroupRotationInfo() works consistently.
			groupRotOffset = qOriAngsInv * level.Vec3Diff(ori.pos, pos);
			groupRotPos = level.Vec3Offset(ori.groupRotPos, qOriGrpAngs * groupRotOffset);

			//Compute the angle deltas and save into all "group angles" so SetGroupRotationInfo() works consistently.
			//Note: this cannot be done by relying on DeltaAngle() results and feeding those results into a quat! (I've tried.)
			groupRotAngDiff = qOriAngsInv * quat.FromAngles(angle, pitch, roll);
			[groupAngle, groupPitch, groupRoll] = AnglesFromQuat(qOriGrpAngs * groupRotAngDiff);

			bQuatAngsAtPole = false;
		}
	}

	//============================
	// AnglesFromQuat
	//============================
	static double, double, double, bool AnglesFromQuat (quat q)
	{
		//Credits and thanks to Boondorl and Lewisk3 for showing me
		//the general patterns behind this algorithm.
		//
		//The singularity test conditions, however, were lifted and adapted from here:
		//https://www.euclideanspace.com/maths/geometry/rotations/conversions/quaternionToEuler/

		double qYaw, qPitch, qRoll;
		bool atPole = true;
		double singularity = q.w * q.y - q.x * q.z;
		if (singularity > 0.4999)
		{
			qYaw = -2 * atan2(q.x, q.w);
			qPitch = 90;
			qRoll = 0;
		}
		else if (singularity < -0.4999)
		{
			qYaw = 2 * atan2(q.x, q.w);
			qPitch = -90;
			qRoll = 0;
		}
		else
		{
			atPole = false;
			double ySquared = q.y * q.y;

			double angY = 2 * (q.w * q.z + q.x * q.y);
			double angX = 1.0 - 2 * (ySquared + q.z * q.z);
			qYaw = atan2(angY, angX);

			qPitch = asin(2 * singularity);

			angY = 2 * (q.w * q.x + q.y * q.z);
			angX = 1.0 - 2 * (q.x * q.x + ySquared);
			qRoll = atan2(angY, angX);
		}
		return qYaw, qPitch, qRoll, atPole;
	}

	//============================
	// CanCollideWith (override)
	//============================
	override bool CanCollideWith (Actor other, bool passive)
	{
		let plat = FishyPlatform(other);
		if (plat)
		{
			if (plat == portTwin)
				return false; //Don't collide with portal twin

			if (group && group == plat.group)
				return false; //Don't collide with groupmates

			if (portTwin && portTwin.group && portTwin.group == plat.group)
				return false; //Don't collide with portal twin's groupmates

			if (options & OPTFLAG_IGNOREGEO)
				return false; //Don't collide with any platform in general
		}

		if (passive)
		{
			if (stuckActors.Find(other) < stuckActors.Size())
				return false; //Let stuck things move out/move through us - also makes pushing them away easier

			//Allow the other actor to step up on us.
			//Well, they'd actually noclip into us but GetStuckActors() and HandleStuckActors() should take care of that.
			if (!other.bMissile && !other.bSkullFly && IsCarriable(other) && //Ignore missiles, charging monsters, and non-carriables
				other.bInChase && //This thing must be calling A_Chase or A_Wander
				(pos.z + height) - other.pos.z <= other.maxStepHeight ) //Its 'maxStepHeight' allows it to step up on us
			{
				return false;
			}
		}

		if (bInMove || (portTwin && portTwin.bInMove))
		{
			//If me or my twin is moving, don't
			//collide with either one's passengers.
			let grp = bPortCopy ? portTwin.group : self.group;
			int gSize = grp ? grp.members.Size() : 0;
			for (int i = -1; i < gSize; ++i)
			{
				plat = (i == -1) ? self : grp.members[i]; //Not calling GetMember() here because that deletes null entries and nothing is supposed to change here

				if (i > -1 && (!plat || plat == self)) //Already handled self
					continue;

				if (plat != self && (!grp.origin || !(grp.origin.options & OPTFLAG_DIFFPASSCOLL))) //If desired, don't collide with any groupmate's passengers either
					break;

				if (plat.passengers.Find(other) < plat.passengers.Size())
					return false;

				if (plat.portTwin && plat.portTwin.passengers.Find(other) < plat.portTwin.passengers.Size())
					return false;
			}
		}
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

		if (a.bNoClip || b.bNoClip)
			return false;

		if ((a.bAllowThruBits || b.bAllowThruBits) && (a.thruBits & b.thruBits))
			return false;

		if ((a.bThruSpecies || b.bThruSpecies) && a.GetSpecies() == b.GetSpecies())
			return false;

		if ((a.player && (a.player.cheats & (CF_NOCLIP|CF_NOCLIP2))) || (b.player && (b.player.cheats & (CF_NOCLIP|CF_NOCLIP2))))
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
	static bool FitsAtPosition (Actor mo, vector3 testPos, bool ignoreActors = false, bool onlyCheckMove = false)
	{
		//Unlike TestMobjLocation(), CheckMove() takes into account
		//actors that have the flags FLOORHUGGER, CEILINGHUGGER
		//and CANTLEAVEFLOORPIC.

		let oldThruActors = mo.bThruActors;
		if (ignoreActors)
			mo.bThruActors = true; //Makes P_CheckPosition() not iterate through the thing blockmap; it skips calling PIT_CheckThing()
		let oldZ = mo.pos.z;
		mo.SetZ(testPos.z); //Because setting Z has an effect on CheckMove()'s outcome

		FCheckPosition tm;
		bool result = (mo.CheckMove(testPos.xy, 0, tm) && (onlyCheckMove ||
			(testPos.z >= tm.floorZ &&					//This is something that TestMobjLocation() checks
			testPos.z + mo.height <= tm.ceilingZ) ) );	//and that CheckMove() does not account for.

		mo.bThruActors = oldThruActors;
		mo.SetZ(oldZ);
		return result;
	}

	//============================
	// IsBehindLine
	//============================
	static clearscope bool IsBehindLine (vector2 v, Line l)
	{
		return level.PointOnLineSide(v, l);
	}

	//============================
	// GetCrushDamageSource
	//============================
	virtual Actor, Name GetCrushDamageSource (Actor dmgSrc)
	{
		// Determine if anyone should take blame for
		// causing crush damage and what the
		// damage type should be.
		//
		// 'dmgSrc' is the "pusher"
		// which may or may not be the platform itself.
		//
		// By default nobody takes the blame
		// and damage type is "Crush."
		return null, 'Crush';
	}

	//============================
	// CrushObstacle
	//============================
	private bool CrushObstacle (Actor pushed, bool noPush, bool fits, Actor pusher)
	{
		// Helper function for PushObstacle().
		// Retuns false if 'pushed' was destroyed.
		//
		// Normally, if the obstacle is pushed against a wall or solid actor etc
		// then apply damage every 4th tic so its pain sound can be heard.
		// But if it's not pushed against anything and 'hurtfulPush' is enabled
		// then always apply damage.
		// However, if there was no 'pushForce' whatsoever and 'hurtfulPush' is
		// desired then the "damage every 4th tic" rule always applies.
		bool hurtfulPush = (options & OPTFLAG_HURTFULPUSH);
		Actor dmgSrc;
		Name dmgType;

		if (noPush)
		{
			if (hurtfulPush && !(level.mapTime & 3))
			{
				[dmgSrc, dmgType] = GetCrushDamageSource(pusher);
				int doneDamage = pushed.DamageMobj(dmgSrc, dmgSrc, crushDamage, dmgType);
				pushed.TraceBleed(doneDamage > 0 ? doneDamage : crushDamage, pusher);
			}
		}
		else
		{
			//If it 'fits' then it's not being pushed against anything
			if ((!fits && !(level.mapTime & 3)) || (fits && hurtfulPush))
			{
				[dmgSrc, dmgType] = GetCrushDamageSource(pusher);
				int doneDamage = pushed.DamageMobj(dmgSrc, dmgSrc, crushDamage, dmgType);
				pushed.TraceBleed(doneDamage > 0 ? doneDamage : crushDamage, pusher);
			}
		}
		return (pushed && !pushed.bDestroyed);
	}

	//============================
	// PushObstacle
	//============================
	private void PushObstacle (Actor pushed, vector3 pushForce = (double.nan, 0, 0), Actor pusher = null, vector2 pushPoint = (double.nan, 0))
	{
		//Under certain cases, 'pusher' can be a generic non-platform actor
		if (!pusher)
			pusher = self;

		if ((pusher.bCannotPush && (pusher != self || stuckActors.Find(pushed) >= stuckActors.Size() ) ) || //Can't push it if we have CANNOTPUSH and this isn't an actor that's stuck in us.
			(!pushed.bPushable && //Always push actors that have PUSHABLE.
			(pushed.bDontThrust || pushed is "FishyPlatform") ) ) //Otherwise, only push it if it's a non-platform and doesn't have DONTTHRUST.
		{
			if (crushDamage > 0 && (options & OPTFLAG_HURTFULPUSH))
				CrushObstacle(pushed, true, true, pusher); //Handle OPTFLAG_HURTFULPUSH
			return; //No velocity modification
		}

		if (pushForce != pushForce) //NaN check
			pushForce = level.Vec3Diff(pusher.pos, pushed.pos).Unit();

		if (pushed.bPushable)
		{
			pushForce *= pushed.pushFactor; //Scale by its 'pushFactor' if it has +PUSHABLE
		}
		else
		{
			//For actors without +PUSHABLE the 'pushForce' will be scaled down,
			//but only if it's slightly larger than a unit vector.
			//The scaled down force will still be slightly larger than a unit vector.
			double len = pushForce.Length();
			if (len > 1.1 && (len /= 8) > 1.1)
				pushForce = pushForce.Unit() * len;
		}

		//The 'pushPoint' may not be where 'pusher' is right now
		if (pushPoint != pushPoint) //NaN check
			pushPoint = pusher.pos.xy;

		bool deliveredOuchies = false;
		bool fits = false;
		double pushAng, angToPushed;

		//Don't accept close-to-zero velocity
		if (abs(pushForce.x) < minVel) pushForce.x = 0;
		if (abs(pushForce.y) < minVel) pushForce.y = 0;
		if (abs(pushForce.z) < minVel) pushForce.z = 0;

		//If there's gonna be a push attempt and this is a +PUSHABLE thing, play its push sound
		if (pushForce != (0, 0, 0) && pushed.bPushable)
			pushed.PlayPushSound();

		bool doZPushTest = false;
		if (pushForce.z)
		{
			let pusherPos = pusher.pos;
			pusher.SetXYZ((pushPoint, pusher.pos.z)); //Needed for OverlapXY()
			doZPushTest = OverlapXY(pusher, pushed);
			pusher.SetXYZ(pusherPos);
		}

		if (doZPushTest)
		{
			//Handle vertical obstacle pushing first - (what happens if it can't be pushed up or down)
			fits = FitsAtPosition(pushed, level.Vec3Offset(pushed.pos, pushForce));
			if (!fits)
			{
				Line bLine = pushed.blockingLine;
				if (bLine && bLine.special && pushed.bCanPushWalls) //Check if blocking line has a push special
				{
					bLine.Activate(pushed, IsBehindLine(pushed.pos.xy, bLine), SPAC_Push);
					if (!pushed || pushed.bDestroyed)
						return; //Actor 'pushed' was destroyed
				}

				if (crushDamage > 0 && !CrushObstacle(pushed, false, false, pusher))
					return; //Actor 'pushed' was destroyed
				deliveredOuchies = true;

				if (pushForce.xy == (0, 0))
				{
					pushForce.x = max(0.2, abs(pushForce.z)); //Need some meaningful velocity
					pushAng = 0;
				}
				else
				{
					pushAng = VectorAngle(pushForce.x, pushForce.y);
				}
				vector2 diff = level.Vec2Diff(pushPoint, pushed.pos.xy);
				angToPushed = VectorAngle(diff.x, diff.y);

				//Try to push away obstacle from 'pushPoint' in a cardinal direction
				int carDir;
				if (abs(angToPushed) <= 45)
					carDir = 0;
				else if (abs(angToPushed) <= 135)
					carDir = (angToPushed < 0) ? -90 : 90;
				else
					carDir = 180;

				double delta = DeltaAngle(pushAng, carDir);
				if (delta)
				{
					pushAng += delta;
					pushForce.xy = RotateVector(pushForce.xy, delta);
				}
				pushForce.z = 0;
			}
		}
		else
		{
			pushForce.z = 0;
		}

		if (!fits && pushForce.xy != (0, 0))
		{
			//Handle horizontal obstacle pushing - (what happens if it can't be pushed because a wall or a solid actor is in the way)
			fits = FitsAtPosition(pushed, level.Vec3Offset(pushed.pos, pushForce), false, true);
			if (!fits)
			{
				Line bLine = pushed.blockingLine;
				if (bLine && bLine.special && pushed.bCanPushWalls) //Check if blocking line has a push special
				{
					bLine.Activate(pushed, IsBehindLine(pushed.pos.xy, bLine), SPAC_Push);
					if (!pushed || pushed.bDestroyed)
						return; //Actor 'pushed' was destroyed
				}

				if (!deliveredOuchies)
				{
					if (crushDamage > 0 && !CrushObstacle(pushed, false, false, pusher))
						return; //Actor 'pushed' was destroyed
					deliveredOuchies = true;

					pushAng = VectorAngle(pushForce.x, pushForce.y);
					vector2 diff = level.Vec2Diff(pushPoint, pushed.pos.xy);
					angToPushed = VectorAngle(diff.x, diff.y);
				}

				//Can't push obstacle in the direction we're going, so try to move it aside instead
				double delta = DeltaAngle(pushAng, angToPushed);
				pushForce.xy = RotateVector(pushForce.xy, (delta >= 0) ? 90 : -90);
			}
		}

		if (pushed.bCantLeaveFloorPic || //No Z pushing for CANTLEAVEFLOORPIC actors.
			pushed.bFloorHugger || pushed.bCeilingHugger) //No Z pushing for floor/ceiling huggers.
		{
			pushForce.z = 0;
		}

		if (!pushed.bPushable)
		{
			//Don't apply 'pushForce' if the obstacle's velocity speed is equal to or exceeds the 'pushForce' in a particular direction
			if ((pushForce.x < 0 && pushed.vel.x <= pushForce.x) || (pushForce.x > 0 && pushed.vel.x >= pushForce.x)) pushForce.x = 0;
			if ((pushForce.y < 0 && pushed.vel.y <= pushForce.y) || (pushForce.y > 0 && pushed.vel.y >= pushForce.y)) pushForce.y = 0;
			if ((pushForce.z < 0 && pushed.vel.z <= pushForce.z) || (pushForce.z > 0 && pushed.vel.z >= pushForce.z)) pushForce.z = 0;
		}

		pushed.vel += pushForce; //Apply the actual push (unrelated to damage)

		if (!deliveredOuchies && crushDamage > 0 && (options & OPTFLAG_HURTFULPUSH))
			CrushObstacle(pushed, (pushForce == (0, 0, 0)), true, pusher); //Handle OPTFLAG_HURTFULPUSH
	}

	//============================
	// SetTravelSpeed
	//============================
	private void SetTravelSpeed (int speed)
	{
		if (!speed)
		{
			timeFrac = 1.0; //Zero speed means "instant"
		}
		else
		{
			double distance = (pNext - pCurr).Length();
			if (distance ~== 0 && !(options & OPTFLAG_FACEMOVE))
			{
				//If two interpolation points occupy the same spot,
				//determine distance by picking the longest
				//interpolation angle instead.
				//(Unless "face movement direction" is enabled.)
				double ang = ((options | acsFlags) & OPTFLAG_ANGLE) ? abs(pNextAngs.x - pCurrAngs.x) : 0;
				double pi =  ((options | acsFlags) & OPTFLAG_PITCH) ? abs(pNextAngs.y - pCurrAngs.y) : 0;
				double ro =  ((options | acsFlags) & OPTFLAG_ROLL)  ? abs(pNextAngs.z - pCurrAngs.z) : 0;
				distance = max(ang, pi, ro);
			}

			if (distance <= speed || (distance /= speed) < 1.1)
				timeFrac = 1.0; //Too fast
			else
				timeFrac = 1.0 / distance;
		}
	}

	//============================
	// SetTimeFraction
	//============================
	private void SetTimeFraction ()
	{
		if (!currNode)
			return;

		int newTime = currNode.args[NODEARG_TRAVELTIME];
		if (newTime <= 0) //Negative values are speed in map units per tic
		{
			SetTravelSpeed(-newTime);
			return;
		}

		if (currNode is "FishyPlatformNode")
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
			timeFrac = 8.0 / (newTime * TICRATE);
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

		if (currNode is "FishyPlatformNode")
		{
			switch (currNode.args[NODEARG_HOLDTUNIT])
			{
				default:
				case TIMEUNIT_OCTICS:
					holdTime = newTime * TICRATE / 8;
					break;
				case TIMEUNIT_TICS:
					holdTime = newTime;
					break;
				case TIMEUNIT_SECS:
					holdTime = newTime * TICRATE;
					break;
			}
		}
		else //Old InterpolationPoint class, always in octics
		{
			holdTime = newTime * TICRATE / 8;
		}
	}

	//============================
	// SetInterpolationCoordinates
	//============================
	private void SetInterpolationCoordinates (vector3 currPos, vector3 currAngs)
	{
		InterpolationPoint nextNode = !currNode ? null :
			bGoToNode ? currNode : currNode.next;

		FishyPlatformNode platNode = !nextNode ? null :
			FishyPlatformNode(nextNode);

		bIgnorePivot = (platNode && platNode.user_ignorepivot);
		bool noPosChange = (platNode && platNode.HasNoPosChange());
		vector3 offset = (0, 0, 0);

		//Take into account angle changes when
		//passing through non-static line portals.
		//All checked angles have to be adjusted.
		if (prevNode && !bGoToNode)
		{
			if (!noPosChange)
			{
				offset = level.Vec3Diff(currPos, prevNode.pos); //Make it portal aware in a way so TryMove() can handle it
				if (platNode)
					offset = platNode.FilterNoPosChange(noChange: (0, 0, 0), yesChange: offset);
			}
			pPrev = currPos + offset;
			pPrevAngs = (
			Normalize180(prevNode.angle + portDelta),
			Normalize180(prevNode.pitch),
			Normalize180(prevNode.roll));
		}

		pCurr = currPos; //This is deliberately not "currNode.pos" because we might have crossed a portal while following our path
		if (!prevNode || bGoToNode)
		{
			pCurrAngs = (
			Normalize180(currAngs.x), //This is deliberately not "currNode.angle/pitch/roll" for the same reason
			Normalize180(currAngs.y),
			Normalize180(currAngs.z));
		}
		else
		{
			pCurrAngs = pPrevAngs + (
			DeltaAngle(pPrevAngs.x, currAngs.x),
			DeltaAngle(pPrevAngs.y, currAngs.y),
			DeltaAngle(pPrevAngs.z, currAngs.z));
		}

		if (nextNode)
		{
			if (!noPosChange)
			{
				offset = level.Vec3Diff(currPos, nextNode.pos); //Make it portal aware in a way so TryMove() can handle it
				if (platNode)
					offset = platNode.FilterNoPosChange(noChange: (0, 0, 0), yesChange: offset);
			}
			pNext = currPos + offset;
			pNextAngs = pCurrAngs + (
			DeltaAngle(pCurrAngs.x, nextNode.angle + portDelta),
			DeltaAngle(pCurrAngs.y, nextNode.pitch),
			DeltaAngle(pCurrAngs.z, nextNode.roll));

			if (nextNode.next && !bGoToNode)
			{
				if (!noPosChange)
				{
					offset = level.Vec3Diff(currPos, nextNode.next.pos); //Make it portal aware in a way so TryMove() can handle it
					if (platNode)
						offset = platNode.FilterNoPosChange(noChange: (0, 0, 0), yesChange: offset);
				}
				pLast = currPos + offset;
				pLastAngs = pNextAngs + (
				DeltaAngle(pNextAngs.x, nextNode.next.angle + portDelta),
				DeltaAngle(pNextAngs.y, nextNode.next.pitch),
				DeltaAngle(pNextAngs.z, nextNode.next.roll));
			}
			else // (!nextNode.next || bGoToNode)
			{
				pLast = pNext;
				pLastAngs = pNextAngs;
			}
		}
		else // (!nextNode)
		{
			pNext = pCurr;
			pLast = pCurr;
			pNextAngs = pCurrAngs;
			pLastAngs = pCurrAngs;
		}

		if (!prevNode || bGoToNode)
		{
			pPrev = pCurr;
			pPrevAngs = pCurrAngs;
		}
	}

	//============================
	// AdjustInterpolationCoordinates
	//============================
	private void AdjustInterpolationCoordinates (vector3 startPos, vector3 endPos, double delta)
	{
		//Used for when crossing portals

		//Offset and possibly rotate the coordinates
		pPrev -= startPos;
		pCurr -= startPos;
		pNext -= startPos;
		pLast -= startPos;
		if (bPivotVectorIsPosition)
			pivotVector -= startPos;

		if (delta)
		{
			pPrevAngs.x += delta;
			pCurrAngs.x += delta;
			pNextAngs.x += delta;
			pLastAngs.x += delta;

			//Rotate them
			double c = cos(delta), s = sin(delta);
			pPrev.xy = (pPrev.x*c - pPrev.y*s, pPrev.x*s + pPrev.y*c);
			pCurr.xy = (pCurr.x*c - pCurr.y*s, pCurr.x*s + pCurr.y*c);
			pNext.xy = (pNext.x*c - pNext.y*s, pNext.x*s + pNext.y*c);
			pLast.xy = (pLast.x*c - pLast.y*s, pLast.x*s + pLast.y*c);
			if (bPivotVectorIsPosition)
				pivotVector.xy = (pivotVector.x*c - pivotVector.y*s, pivotVector.x*s + pivotVector.y*c);
			interpolatedPivotOffset.xy = (
				interpolatedPivotOffset.x*c - interpolatedPivotOffset.y*s,
				interpolatedPivotOffset.x*s + interpolatedPivotOffset.y*c);
		}
		pPrev += endPos;
		pCurr += endPos;
		pNext += endPos;
		pLast += endPos;
		if (bPivotVectorIsPosition)
			pivotVector += endPos;
	}

	//============================
	// IsCarriable
	//============================
	bool IsCarriable (Actor mo)
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

		let plat = FishyPlatform(mo);
		if (plat)
		{
			if (!plat.bCarriable)
				return false;

			//Don't carry platform if it's in our group
			if (group && group == plat.group)
				return false;

			//If either one has OPTFLAG_IGNOREGEO then don't carry it
			if (options == -1) //Not already set through PostBeginPlay()?
				options = args[ARG_OPTIONS];
			if (plat.options == -1) //Ditto
				plat.options = plat.args[ARG_OPTIONS];
			if ((options | plat.options) & OPTFLAG_IGNOREGEO)
				return false;

			//If this is somebody's portal copy, ignore it
			if (plat.bPortCopy)
				return false;

			//A platform in move is the platform that's likely carrying us, ignore it
			if (plat.bInMove || (plat.portTwin && plat.portTwin.bInMove) )
				return false;
		}
		return true;
	}

	//============================
	// CanStealFrom
	//============================
	bool CanStealFrom (FishyPlatform other, Actor mo)
	{
		double myTop = pos.z + height;
		double otherTop = other.pos.z + other.height;

		if (myTop > otherTop)
			return true;

		if (!group || group != other.group || myTop < otherTop)
			return false;

		//'other' is a groupmate with the same top
		return (mo &&
			((options ^ other.options) & OPTFLAG_MIRROR) &&   //Only steal if we have different "mirror" flag settings and
			OverlapXY(self, mo, radius) && !OverlapXY(other, mo, other.radius) ); //'mo' is within our radius and NOT within other's radius.
	}

	//============================
	// ForgetPassenger
	//============================
	private void ForgetPassenger (int index)
	{
		let plat = FishyPlatform(passengers[index]);
		if (plat && !plat.bDestroyed && plat.group && plat.group.carrier == self)
			plat.group.carrier = null;
		passengers.Delete(index);
	}

	//============================
	// PassengerPreMove
	//============================
	virtual void PassengerPreMove (Actor mo)
	{
		// This is called every time before a (potential) passenger (called 'mo')
		// is moved.
	}

	//============================
	// PassengerPostMove
	//============================
	virtual void PassengerPostMove (Actor mo, bool moved)
	{
		// This is called every time after a (potential) passenger (called 'mo')
		// was tried to be moved.
		//
		// 'moved' will be true if 'mo' was moved successfully,
		// otherwise it will be false.
		//
		// The distinction is useful if you want to run code only if the
		// passenger (mo) was moved or not moved.
	}

	//============================
	// SpecialBTIActor
	//============================
	virtual bool SpecialBTIActor (Actor mo)
	{
		// Use this to handle special actors that aren't being pointed by passengers
		// (and thus can't be handled in the PassengerPre/PostMove() functions)
		// but can still be detected in a BlockThingsIterator (BTI) search.
		//
		// Return 'true' if the actor shouldn't be processed
		// and skip to the next blockmap result.
		//
		// Or return 'false' to run the usual checks in
		// GetNewPassengers() and GetStuckActors().
		// The "usual checks" being:
		// Is it within XY and Z range, is it a corpse,
		// is it solid, is it carriable, is it a stuck actor, etc, etc.
		return false;
	}

	//============================
	// GetNewBmapResults
	//============================
	private void GetNewBmapResults (bool forceRun = false)
	{
		// Just creating one BTI or one BLI per tic takes up unnecessary processing time (according to "profilethinkers")
		// and creates a lot of garbage for the GC (according to "stat gc").
		// To mitigate that, the iterators will be created once per some arbitrary number of tics.
		//
		// Since this is done at an interval the search radius should be larger too
		// to give a better chance of catching things.
		//
		// ...Unless of course fetching blockmap results every tic (ie. "in realtime") is desired.

		if (level.mapTime == lastGetBmapTime && !forceRun)
			return; //Already called in this tic
		lastGetBmapTime = level.mapTime;

		nearbyActors.Clear();

		//A portal copy that's not in use shouldn't do anything besides clear its 'nearbyActors' array
		if (bPortCopy && bNoBlockmap)
			return;

		bool realtime = (options & OPTFLAG_REALTIMEBMAP);

		let iteratorRadius = radius;
		if (!realtime || pos ~== oldPos) //If idle, still use a bigger radius for the sake of GetStuckActors()
			iteratorRadius *= BMAP_RADIUS_MULTIPLIER;

		let bti = BlockThingsIterator.Create(self, iteratorRadius);
		while (bti.Next())
		{
			let mo = bti.thing;
			if (mo == self || mo == portTwin)
				continue; //Ignore self and portal twin

			//If we're doing realtime blockmap searching
			//then accept this actor unconditionally.
			//Because all the relevant checks (including distance)
			//will be done elsewhere.
			if (realtime)
			{
				nearbyActors.Push(mo);
				continue;
			}

			//Otherwise, only accept this actor if it has certain attributes
			if (mo.bCanPass || //Can move by itself (relevant for GetStuckActors())
				(mo.bCorpse && !mo.bDontGib) || //A corpse (relevant for corpse grinding)
				(mo.bSpecial && mo is "Inventory") || //Item that can be picked up (relevant for Z position correction)
				IsCarriable(mo) || //A potential passenger
				(CollisionFlagChecks(self, mo) && self.CanCollideWith(mo, false) && mo.CanCollideWith(self, true) ) ) //A solid actor
			{
				//We don't want the resulting array size to be too large because
				//it's a waste of time checking so many actors that are simply out of reach.
				//But do be a little overboard with our 'blockDist'.
				double blockDist = iteratorRadius + mo.radius + mo.speed + mo.vel.xy.Length();
				if (abs(bti.position.x - mo.pos.x) < blockDist && abs(bti.position.y - mo.pos.y) < blockDist)
					nearbyActors.Push(mo);
			}
		}

		if (bSearchForUPorts) //Only do a search if there's something to look for (and we're not a portal copy)
		{
			nearbyUPorts.Clear();

			if (realtime)
				iteratorRadius = radius + EXTRA_SIZE;

			let bli = BlockLinesIterator.Create(self, iteratorRadius);
			while (bli.Next())
			{
				let type = bli.curLine.GetPortalType();
				if (type == LinePortal.PORTT_TELEPORT || type == LinePortal.PORTT_INTERACTIVE) //We don't want static (linked) portals
					nearbyUPorts.Push(bli.curLine);
			}
		}

		noBmapSearchTics = realtime ? 0 : BMAP_SEARCH_INTERVAL;
		oldBmapSearchPos = pos.xy; //If we're too far away from this position then this function will be called earlier (see Tick())
	}

	//============================
	// GetNewPassengers
	//============================
	private bool GetNewPassengers (bool ignoreObs)
	{
		// In addition to fetching passengers, this is where corpses get crushed, too. Items won't get destroyed.
		// Returns false if one or more actors are completely stuck inside platform unless 'ignoreObs' is true.

		if (lastGetNPTime == level.mapTime)
			return lastGetNPResult; //Already called in this tic
		lastGetNPTime = level.mapTime;

		double top = pos.z + height;
		Array<Actor> miscActors; //The actors on top of or stuck inside confirmed passengers (We'll move those, too)
		Array<Actor> newPass; //Potential new passengers, usually (but not always) detected on top of us
		Array<FishyPlatform> otherPlats;

		//Four things to do here when iterating thru 'nearbyActors' array:
		//1) Gather eligible passengers.
		//2) Gather stuck actors.
		//3) Turn corpses into gibs.
		//4) Help nearby monsters step/walk on us (if their maxStepHeight property allows it).
		bool result = true;

		for (uint iActors = nearbyActors.Size(); iActors-- > 0;)
		{
			let mo = nearbyActors[iActors];
			if (!mo || mo.bDestroyed)
			{
				nearbyActors.Delete(iActors);
				continue;
			}

			if (mo.bNoBlockmap)
				continue;

			if (SpecialBTIActor(mo))
				continue; //Already handled

			let plat = FishyPlatform(mo);
			if (plat)
				otherPlats.Push(plat);

			bool oldPass = (passengers.Find(mo) < passengers.Size());
			bool canCarry = ((!portTwin || portTwin.passengers.Find(mo) >= portTwin.passengers.Size()) && //Don't take your twin's passengers here
						IsCarriable(mo));

			if (plat && (plat.bInMove || (plat.portTwin && plat.portTwin.bInMove) ) ) //This is probably the platform that's carrying/moving us
			{
				if (!ignoreObs && !bOnMobj &&
					(abs(pos.z - (mo.pos.z + mo.height)) <= TOP_EPSILON || //Are we standing on 'mo'?
					OverlapZ(self, mo) ) && OverlapXY(self, mo) )
				{
					bOnMobj = true;
				}
				continue;
			}

			//'ignoreObs' makes anything above our 'top' legit unless there's a 3D floor in the way.
			if (mo.pos.z >= top - TOP_EPSILON && (ignoreObs || mo.pos.z <= top + TOP_EPSILON) && //On top of us?
				mo.floorZ <= top + TOP_EPSILON) //No 3D floor above our 'top' that's below 'mo'?
			{
				if (canCarry && !oldPass)
				{
					if (OverlapXY(self, mo))
						newPass.Push(mo);
					else
						miscActors.Push(mo); //We'll compare this later against the passengers
				}
				continue;
			}

			if (OverlapZ(self, mo) && OverlapXY(self, mo))
			{
				if (mo.bCorpse && !mo.bDontGib && mo.tics == -1 && !bNoCorpseGib) //Let dying actors finish their death sequence
				{
					if (!ignoreObs)
						mo.Grind(false);
					continue;
				}

				bool solidMo = (CollisionFlagChecks(self, mo) &&
					self.CanCollideWith(mo, false) && mo.CanCollideWith(self, true) );

				if (solidMo ||
					(mo.bSpecial && mo is "Inventory") ) //Item that can be picked up?
				{
					//Try to correct 'mo' Z so it can ride us, too.
					//But only if its 'maxStepHeight' allows it.
					bool fits = false;
					if (canCarry && top - mo.pos.z <= mo.maxStepHeight)
					{
						if (plat)
						{
							fits = plat.DoPlatZFix(top, self);
						}
						else
						{
							PassengerPreMove(mo);
							fits = FitsAtPosition(mo, (mo.pos.xy, top), true);
							if (fits)
							{
								mo.SetZ(top);
								mo.CheckPortalTransition(); //Handle sector portals properly
							}
							PassengerPostMove(mo, fits);
						}

						if (fits && passengers.Find(mo) >= passengers.Size())
							newPass.Push(mo);
					}

					if (solidMo && !fits && !ignoreObs)
					{
						result = false;
						bOnMobj = true;
						if (stuckActors.Find(mo) >= stuckActors.Size())
							stuckActors.Push(mo);
					}
				}
				continue;
			}

			if (!ignoreObs && !bOnMobj &&
				abs(pos.z - (mo.pos.z + mo.height)) <= TOP_EPSILON && //Are we standing on 'mo'?
				CollisionFlagChecks(self, mo) && OverlapXY(self, mo) &&
				self.CanCollideWith(mo, false) && mo.CanCollideWith(self, true) )
			{
				bOnMobj = true;
				continue;
			}

			if (canCarry && !oldPass && mo.bOnMobj)
				miscActors.Push(mo);
		}

		if (newPass.Size() || miscActors.Size())
		{
			//Take into account the possibility that not all
			//group members can be found in a blockmap search.
			if (group)
			for (int iPlat = 0; iPlat < group.members.Size(); ++iPlat)
			{
				let plat = group.GetMember(iPlat);
				if (plat && plat != self && otherPlats.Find(plat) >= otherPlats.Size())
					otherPlats.Push(plat);
			}

			//Go through the other detected platforms (and our groupmates)
			//and see if we can steal some of their passengers.
			for (uint iPlat = otherPlats.Size(); iPlat-- > 0 && (newPass.Size() || miscActors.Size());)
			{
				let plat = otherPlats[iPlat];
				if (!plat.passengers.Size())
					continue;

				for (uint i = newPass.Size(); i-- > 0;)
				{
					let index = plat.passengers.Find(newPass[i]);
					if (index < plat.passengers.Size())
					{
						if (CanStealFrom(plat, newPass[i]))
							plat.ForgetPassenger(index);
						else
							newPass.Delete(i);
					}
				}
				for (uint i = miscActors.Size(); i-- > 0;)
				{
					if (plat.passengers.Find(miscActors[i]) < plat.passengers.Size())
						miscActors.Delete(i);
				}
			}
			passengers.Append(newPass);

			//Now figure out which of the misc actors are on top of/stuck inside
			//established passengers.
			for (int i = 0; miscActors.Size() && i < passengers.Size(); ++i)
			{
				let mo = passengers[i];
				if (!mo)
				{
					//In this case it's detrimental to go back-to-front on the 'passengers' array
					//because of the below for loop. (Potential new passengers get added and we need
					//to compare anything that's still in 'miscActors' with these new passengers.)
					//Decrement 'i' so that when this loop increments it again it points to
					//the correct array entry.
					ForgetPassenger(i--);
					continue;
				}
				double moTop = mo.pos.z + mo.height;

				for (uint iOther = miscActors.Size(); iOther-- > 0;)
				{
					let otherMo = miscActors[iOther];

					if ( ( abs(otherMo.pos.z - moTop) <= TOP_EPSILON || OverlapZ(mo, otherMo) ) && //Is 'otherMo' on top of 'mo' or stuck inside 'mo'?
						OverlapXY(mo, otherMo) ) //Within XY range?
					{
						miscActors.Delete(iOther); //Don't compare this one against other passengers anymore
						passengers.Push(otherMo);
					}
				}
			}
		}

		//If we have passengers that are grouped platforms,
		//prune 'passengers' array; we only want one member per group.
		//Preferably the origin if active, else the closest member.
		Array<FishyPlatformGroup> otherGroups;
		for (uint i = passengers.Size(); i-- > 0;)
		{
			let plat = FishyPlatform(passengers[i]);
			if (!plat || !plat.group)
				continue;

			if (otherGroups.Find(plat.group) < otherGroups.Size())
			{
				passengers.Delete(i); //Already dealt with this group
				continue;
			}
			otherGroups.Push(plat.group);

			//Since we are dealing with groups it is likely the 'carrier'
			//is outside of the blockmap search. That's why it's a pointer
			//in the group class.
			if (plat.group.carrier && plat.group.carrier != self)
			{
				if (!CanStealFrom(plat.group.carrier, null))
				{
					passengers.Delete(i); //Can't take any of this group's members
					continue;
				}

				//Make group cut ties with current carrier before self becomes the new carrier
				let carrier = plat.group.carrier;
				for (int iMember = 0; carrier.passengers.Size() && iMember < plat.group.members.Size(); ++iMember)
				{
					let member = plat.group.GetMember(iMember);
					if (!member)
						continue;

					int index = carrier.passengers.Find(member);
					if (index < carrier.passengers.Size())
						carrier.passengers.Delete(index);
				}
			}
			plat.group.carrier = self;

			if (plat.group.origin && plat.IsActive())
			{
				passengers[i] = plat.group.origin;
				continue;
			}

			//No active origin, so pick the closest member.
			double dist = Distance3D(plat);
			for (int iMember = 0; iMember < plat.group.members.Size(); ++iMember)
			{
				let member = plat.group.GetMember(iMember);
				if (member && member != plat)
				{
					double thisDist = Distance3D(member);
					if (thisDist < dist)
					{
						dist = thisDist;
						passengers[i] = member;
					}
				}
			}

			let newOri = FishyPlatform(passengers[i]);
			if (plat.group.origin != newOri)
				plat.SetGroupOrigin(newOri);
		}
		lastGetNPResult = result;
		return result;
	}

	//============================
	// MustGetNewPassengers
	//============================
	private void MustGetNewPassengers ()
	{
		//For cases where the search tic rate must be ignored.
		//(Handle portal twin and groupmates, too.)
		for (int i = -1; i == -1 || (group && i < group.members.Size()); ++i)
		{
			let plat = (i == -1) ? self : group.GetMember(i);
			if (i > -1 && (!plat || plat == self)) //Already handled self
				continue;

			for (int iTwins = 0; iTwins < 2; ++iTwins)
			{
				if (iTwins > 0 && !(plat = plat.portTwin))
					break;

				plat.GetNewBmapResults();
				plat.GetNewPassengers(false);
			}
		}
	}

	//============================
	// UnlinkPassengers
	//============================
	private void UnlinkPassengers ()
	{
		// The goal is to move all passengers as if they were one entity.
		// The only things that should block any of them are
		// non-passengers and geometry.
		// The exception is if a passenger can't fit at its new position
		// in which case it will be "solid" for the others.
		//
		// To accomplish this each of them will temporarily
		// be removed from the blockmap.
		//
		// It's a gross hack for sure, but most of the time these
		// are generic actors that have no way to be aware of the platform
		// or each other for the purpose of non-collision.
		// Another idea might be to use the ThruBits property but
		// that's limited to 32 groups max while this way guarantees
		// they'll be non-solid to each other during this move only
		// while maintaining their usual collision rules with non-passengers.
		//
		// In a custom game/mod it would be cleaner to do the non-collision
		// in a CanCollideWith() override for the passenger.
		// At this moment there's no way to inject code or override
		// CanCollideWith() with pre-existing or unknown actor classes.

		for (int iTwins = 0; iTwins < 2; ++iTwins)
		{
			let plat = (iTwins == 0) ? self : portTwin;

			if (plat)
			for (uint iPass = plat.passengers.Size(); iPass-- > 0;)
			{
				let mo = plat.passengers[iPass];
				if (mo && !mo.bNoBlockmap) //If it has NOBLOCKMAP now, assume it's an inventory item that got picked up
				{
					plat.PassengerPreMove(mo);
					mo.A_ChangeLinkFlags(NO_BMAP);
				}
				else
				{
					plat.ForgetPassenger(iPass);
				}
			}
		}
	}

	//============================
	// LinkPassengers
	//============================
	private void LinkPassengers (bool moved)
	{
		//Link them back into the blockmap after they have been moved
		for (int iTwins = 0; iTwins < 2; ++iTwins)
		{
			let plat = (iTwins == 0) ? self : portTwin;

			if (plat)
			for (uint iPass = plat.passengers.Size(); iPass-- > 0;)
			{
				let mo = plat.passengers[iPass];
				if (mo && mo.bNoBlockmap)
					mo.A_ChangeLinkFlags(YES_BMAP);
				if (mo)
					plat.PassengerPostMove(mo, moved);
			}
		}
	}

	//============================
	// MovePassengers
	//============================
	private bool MovePassengers (vector3 startPos, vector3 endPos, double forward, double delta, double piDelta, double roDelta, bool teleMove)
	{
		// Returns false if a blocked passenger would block the platform's movement unless 'teleMove' is true.

		if (!passengers.Size())
			return true; //No passengers? Nothing to do

		if (bNoPassOrbit)
		{
			delta = 0;
			piDelta = 0;
			roDelta = 0;
		}

		let grp = bPortCopy ? portTwin.group : self.group;
		if (!grp || !grp.origin || !(grp.origin.options & OPTFLAG_DIFFPASSCOLL))
			UnlinkPassengers();

		//Move our passengers (platform rotation is taken into account)
		double top = endPos.z + height;
		double c, s;
		if (delta)
		{
			c = cos(delta);
			s = sin(delta);
		}
		vector2 piAndRoOffset = (0, 0);
		if ((piDelta || roDelta) && !(options & OPTFLAG_NOPITCHROLL))
		{
			piDelta *= 2;
			roDelta *= 2;
			piAndRoOffset = (cos(forward)*piDelta, sin(forward)*piDelta) + //Front/back
				(cos(forward-90)*roDelta, sin(forward-90)*roDelta); //Right/left
		}

		teleMove |= bPlatPorted;
		vector3 pushForce = level.Vec3Diff(startPos, endPos);
		Array<double> preMoveInfo; //Used to save a passenger's pos and angle in case it needs to be restored
		bool usingCompatCrossDropoff = (level.compatflags & 1048576);
		for (int i = passengers.Size(); i-- > 0;)
		{
			let mo = passengers[i];
			let plat = FishyPlatform(mo);

			let moPreMovePos = mo.pos;
			let moPreMoveAngle = mo.angle;
			let moNewAngle = (delta) ? (mo.angle + delta) % 360 : mo.angle;
			let moOldNoDropoff = mo.bNoDropoff;
			let moOldNoGrav = mo.bNoGravity;
			let moOldScrollMove = mo.bScrollMove;

			vector3 offset = level.Vec3Diff(startPos, moPreMovePos);
			if (delta) //Will 'offset' get rotated?
			{
				double oldOffX = offset.x;
				double oldOffY = offset.y;
				double maxDist = radius + mo.radius;

				offset.xy = (offset.x*c - offset.y*s, offset.x*s + offset.y*c); //Rotate it

				//If this passenger is currently within XY range then clamp the rotated offset
				//so that the passenger doesn't end up outside the XY range at its new position
				//and potentially fall off the platform.
				//This is a workaround to the fact that GZDoom/UZDoom (at this moment in time)
				//uses AABB for actor collision. Meaning the collision box never rotates.
				if (abs(oldOffX) < maxDist && abs(oldOffY) < maxDist)
				{
					maxDist -= 1.0;
					offset.x = clamp(offset.x, -maxDist, maxDist);
					offset.y = clamp(offset.y, -maxDist, maxDist);
				}
			}
			offset.xy += piAndRoOffset; //Platform pitch/roll changes may still make passengers fall off; that's intentional

			//No tele move means absolute offset; it needs to be absolute so TryMove() works as expected.
			//Because TryMove() has its own handling of crossing line portals.
			vector3 moNewPos = level.Vec3Offset(endPos, offset, !teleMove);

			//Handle z discrepancy
			if (moNewPos.z < top && moNewPos.z + mo.height >= top)
				moNewPos.z = top;

			bool moved;
			if (plat)
			{
				mo.bNoDropoff = false;
				mo.bNoGravity = true; //Needed so sloped sectors don't block 'mo'
				if (usingCompatCrossDropoff) //Only do this if really necessary
					mo.bScrollMove = true; //Hack: negate the effects of compat_crossdropoff
				if (bPlatPorted)
				{
					plat.bPlatPorted = true;
					plat.platTeleFlags = platTeleFlags;
				}

				PMoveTypes moveType =
					(bPlatPorted) ? MOVE_TRUETELE :
					(teleMove) ? MOVE_TELEPORT :
					MOVE_NORMAL;

				int result = plat.PlatMove(moNewPos, moNewAngle, plat.pitch, plat.roll, moveType);
				if (!mo || mo.bDestroyed)
				{
					ForgetPassenger(i);
					continue;
				}

				moved = (result == 2); //2 == this plat and its groupmates moved. 1 == plat moved but not all groupmates moved.
				if (plat.bFollowingPath)
				{
					//Tried to move an active platform.
					//If we moved it, adjust its
					//interpolation coordinates.
					if (moved)
					{
						if (teleMove)
						{
							plat.AdjustInterpolationCoordinates(moPreMovePos, moNewPos, delta);
						}
						else
						{
							plat.pCurr += moNewPos - moPreMovePos;
							if (moNewPos != mo.pos)
								plat.AdjustInterpolationCoordinates(moNewPos, mo.pos, DeltaAngle(moNewAngle, mo.angle));
						}
					}

					//In the unlikely event the plat has one of the flags CANPUSHWALLS, CANUSEWALLS, ACTIVATEMCROSS or ACTIVATEPCROSS
					//and gets Thing_Remove()'d by activating a line.
					if (mo && !mo.bDestroyed)
					{
						mo.bNoDropoff = moOldNoDropoff;
						mo.bNoGravity = moOldNoGrav;
						if (usingCompatCrossDropoff) //Only do this if really necessary
							mo.bScrollMove = moOldScrollMove;
						mo.A_ChangeLinkFlags(YES_BMAP);
						PassengerPostMove(mo, result);
					}
					ForgetPassenger(i); //Forget this active platform (we won't move it back in case something gets blocked)
					continue;
				}

				if (moved)
					moNewAngle = plat.angle; //In case a portal was crossed that had an angle difference

				if (!mo.bNoBlockmap)
					mo.A_ChangeLinkFlags(NO_BMAP); //Undo SetActorFlag() shenanigans

				mo.bNoDropoff = moOldNoDropoff;
				mo.bNoGravity = moOldNoGrav;
				if (usingCompatCrossDropoff) //Only do this if really necessary
					mo.bScrollMove = moOldScrollMove;
			}
			else if (teleMove)
			{
				if (bPlatPorted)
				{
					moved = mo.Teleport(moNewPos, moNewAngle, platTeleFlags);
					if (!mo || mo.bDestroyed)
					{
						ForgetPassenger(i);
						continue;
					}

					if (!mo.bNoBlockmap)
						mo.A_ChangeLinkFlags(NO_BMAP); //Undo SetActorFlag() shenanigans
				}
				else
				{
					moved = FitsAtPosition(mo, moNewPos);
					if (moved)
						mo.SetOrigin(moNewPos, false);
				}

				if (moved)
					mo.CheckPortalTransition(); //Handle sector portals properly
			}
			else
			{
				int maxSteps = 1;
				vector3 stepMove = level.Vec3Diff(moPreMovePos, moNewPos);

				//If the move is equal or larger than the passenger's radius
				//then it has to be split up into smaller steps.
				//This is needed for proper collision and to ensure
				//lines with specials aren't skipped.
				//NOTE: This was based on similar code from P_XYMovement().
				double maxMove = max(1, mo.radius - 1);
				double moveSpeed = max(abs(stepMove.x), abs(stepMove.y));
				if (moveSpeed > maxMove)
				{
					maxSteps = int(1 + moveSpeed / maxMove);
					stepMove /= maxSteps;
				}

				//NODROPOFF overrides TryMove()'s second argument,
				//but the passenger should be treated like a flying object.
				mo.bNoDropoff = false;
				mo.bNoGravity = true; //Needed so sloped sectors don't block 'mo'
				if (usingCompatCrossDropoff) //Only do this if really necessary
					mo.bScrollMove = true; //Hack: negate the effects of compat_crossdropoff
				moved = true;
				for (int step = 0; step < maxSteps; ++step)
				{
					let moOldAngle = mo.angle;
					mo.AddZ(stepMove.z);
					vector2 tryPos = mo.pos.xy + stepMove.xy;
					if (!mo.TryMove(tryPos, 1))
					{
						mo.AddZ(-stepMove.z);
						moved = false;
						break;
					}

					//Take into account passengers getting Thing_Remove()'d
					//when they activate lines.
					if (!mo || mo.bDestroyed)
						break;

					if (!mo.bNoBlockmap)
						mo.A_ChangeLinkFlags(NO_BMAP); //Undo SetActorFlag() shenanigans

					if (tryPos != mo.pos.xy)
					{
						//If 'mo' has passed through a portal then
						//adjust 'stepMove' if its angle changed.
						double angDiff = DeltaAngle(moOldAngle, mo.angle);
						if (angDiff)
						{
							moNewAngle += angDiff;

							if (step < maxSteps-1)
								stepMove.xy = RotateVector(stepMove.xy, angDiff);

							//Adjust 'moveDir' for monsters
							if (mo.bIsMonster)
								mo.moveDir = (mo.moveDir + int(angDiff / 45)) & 7;
						}
					}
					mo.CheckPortalTransition(); //Handle sector portals properly
				}

				//Take into account passengers getting Thing_Remove()'d
				//when they activate lines.
				if (!mo || mo.bDestroyed)
				{
					ForgetPassenger(i);
					continue;
				}
				mo.bNoDropoff = moOldNoDropoff;
				mo.bNoGravity = moOldNoGrav;
				if (usingCompatCrossDropoff) //Only do this if really necessary
					mo.bScrollMove = moOldScrollMove;
			}

			if (moved)
			{
				if (mo.angle != moNewAngle)
					mo.A_SetAngle(moNewAngle, SPF_INTERPOLATE);

				if (!teleMove)
				{
					//Only remember the old position and angle if 'mo' was moved.
					//(Else we delete the 'passengers' entry containing 'mo', see below.)
					preMoveInfo.Push(moPreMovePos.x);
					preMoveInfo.Push(moPreMovePos.y);
					preMoveInfo.Push(moPreMovePos.z);
					preMoveInfo.Push(moPreMoveAngle);
				}
			}
			else
			{
				if (mo.pos != moPreMovePos || mo.angle != moPreMoveAngle)
				{
					if (!plat)
					{
						if (mo.pos != moPreMovePos)
							mo.SetOrigin(moPreMovePos, true);
						mo.angle = moPreMoveAngle;
					}
					else
					{
						plat.PlatMove(moPreMovePos, moPreMoveAngle, plat.pitch, plat.roll, MOVE_TELEPORT);
					}
				}

				//This passenger will be 'solid' for the others
				mo.A_ChangeLinkFlags(YES_BMAP);
				PassengerPostMove(mo, false);
				ForgetPassenger(i);

				if (teleMove)
					continue;

				//Optionally have passengers push away obstacles.
				//(No need if this passenger is a platform because
				//being a platform it already pushed an obstacle.)
				if (!plat && (options & OPTFLAG_PASSCANPUSH) && mo.blockingMobj)
					PushObstacle(mo.blockingMobj, pushForce, mo);

				Array<Actor> movedBack = { mo };
				for (int iMovedBack = 0; iMovedBack < movedBack.Size(); ++iMovedBack)
				{
					mo = movedBack[iMovedBack];

					//See if this 'mo' would block the platform
					let realPos = pos;
					SetXYZ(endPos);
					bool blocked = (CollisionFlagChecks(self, mo) &&
							OverlapZ(self, mo) && //Within Z range?
							OverlapXY(self, mo) && //Within XY range?
							self.CanCollideWith(mo, false) && mo.CanCollideWith(self, true) );
					SetXYZ(realPos);

					//See if the ones we moved already will collide with this one
					//and if yes, move them back to their old positions.
					//(If the platform's "blocked" then move everyone back unconditionally.)
					for (int iOther = passengers.Size() - 1; iOther >= i; --iOther)
					{
						let otherMo = passengers[iOther];
						if (!blocked && ( !CollisionFlagChecks(otherMo, mo) ||
							!OverlapZ(otherMo, mo) || //Out of Z range?
							!OverlapXY(otherMo, mo) || //Out of XY range?
							!otherMo.CanCollideWith(mo, false) || !mo.CanCollideWith(otherMo, true) ) )
						{
							continue;
						}

						//Put 'otherMo' back at its old position and restore old angle
						int iPreMoveInfo = (passengers.Size() - 1 - iOther) * 4;
						vector3 otherOldPos = (preMoveInfo[iPreMoveInfo], preMoveInfo[iPreMoveInfo + 1], preMoveInfo[iPreMoveInfo + 2]);
						double otherOldAngle = preMoveInfo[iPreMoveInfo + 3];
						plat = FishyPlatform(otherMo);
						if (!plat)
						{
							if (otherMo.pos != otherOldPos)
								otherMo.SetOrigin(otherOldPos, true);
							otherMo.angle = otherOldAngle;
						}
						else
						{
							plat.PlatMove(otherOldPos, otherOldAngle, plat.pitch, plat.roll, MOVE_TELEPORT);
						}
						otherMo.A_ChangeLinkFlags(YES_BMAP);
						PassengerPostMove(otherMo, false);
						preMoveInfo.Delete(iPreMoveInfo, 4);
						ForgetPassenger(iOther);

						if (!blocked)
						{
							movedBack.Push(otherMo);
							otherMo.blockingMobj = mo;
						}
					}

					if (blocked)
					{
						PushObstacle(mo, pushForce, self, startPos.xy);
						if (mo && !mo.bDestroyed && !(mo is "FishyPlatform") && mo != movedBack[0]) //We (potentially) already pushed/crushed the first one's blocker
						{
							//The blocker in this case can only be a former passenger.
							if (mo.blockingMobj)
								PushObstacle(mo.blockingMobj, pushForce, mo);
						}

						if (!grp || !grp.origin || !(grp.origin.options & OPTFLAG_DIFFPASSCOLL))
							LinkPassengers(false);

						return false;
					}
				}
			}
		}

		//Anyone left in the 'passengers' array has moved successfully.
		//Adjust their velocities.
		for (int i = passengers.Size(); i-- > 0;)
		{
			let mo = passengers[i];

			if (mo.bOnMobj && delta) //Standing on platform or on another passenger?
				mo.vel.xy = (mo.vel.x*c - mo.vel.y*s, mo.vel.x*s + mo.vel.y*c); //Rotate its velocity

			//Hack: force UpdateWaterLevel() to make a splash if platform movement isn't too slow and going down
			let oldVelZ = mo.vel.z;
			if (mo.vel.z >= -6)
				mo.vel.z = endPos.z - startPos.z;
			mo.UpdateWaterLevel();
			mo.vel.z = oldVelZ;
		}

		if (!grp || !grp.origin || !(grp.origin.options & OPTFLAG_DIFFPASSCOLL))
			LinkPassengers(true);

		return true;
	}

	//============================
	// HandleOldPassengers
	//============================
	private void HandleOldPassengers (bool letThemWalk)
	{
		// Tracks established passengers and doesn't forget them even if
		// they're above our 'top' (with no 3D floors in between).
		// Such actors are mostly jumpy players and custom AI.
		//
		// Also keep non-flying monsters away from platform's edge.
		// Because the AI's native handling of trying not to
		// fall off of other actors just isn't good enough.

		double top = pos.z + height;
		vector3 velJump = (double.nan, 0, 0);
		bool doVelJump = (options & OPTFLAG_ADDVELJUMP);
		bool passengerCanCross = (options & OPTFLAG_PASSCANCROSS);

		for (uint i = passengers.Size(); i-- > 0;)
		{
			let mo = passengers[i];
			if (!mo || mo.bDestroyed || //Got Thing_Remove()'d?
				mo.bNoBlockmap || !IsCarriable(mo))
			{
				ForgetPassenger(i);
				continue;
			}

			//'floorZ' can be the top of a 3D floor that's right below an actor.
			//No 3D floors means 'floorZ' is the current sector's floor height.
			//(In other words 'floorZ' is not another actor's top that's below.)

			//Is 'mo' below our Z? Or is there a 3D floor above our 'top' that's also below 'mo'?
			if (mo.pos.z < pos.z || mo.floorZ > top + TOP_EPSILON ||
				!OverlapXY(self, mo)) //Is out of XY range?
			{
				//Add velocity to the passenger we just lost track of.
				//It's likely to be a player that has jumped away.
				if (doVelJump)
				{
					if (velJump != velJump) //NaN check
						velJump = level.Vec3Diff(oldPos, pos);
					mo.vel += velJump;
				}
				ForgetPassenger(i);
				continue;
			}

			//See if we should keep it away from the edge
			if (letThemWalk)
				continue; //Nope

			if (!mo.bIsMonster || mo.bNoGravity || mo.bFloat || !mo.speed) //Is not a walking monster?
				continue;

			if (mo.bDropoff || mo.bJumpDown) //Is supposed to fall off of tall drops or jump down?
				continue;

			if (mo.tics != 1 && mo.tics != 0)
				continue; //Don't bother if it's not about to change states (and potentially call A_Chase()/A_Wander())

			if (mo.pos.z > top + TOP_EPSILON)
				continue; //Not exactly on top of us

			if (mo.pos.z - mo.floorZ <= mo.maxDropoffHeight)
				continue; //Monster is close to the ground (which includes 3D floors) so let it walk off

			if (Distance2D(mo) < radius - mo.speed)
				continue; //Not close to platform's edge

			//If there are nearby "bridge" actors (like another platform),
			//let 'mo' cross over.
			if (passengerCanCross)
			{
				let oldBridge = bActLikeBridge;
				bActLikeBridge = false; //So self can't be the 'stepThing'
				FCheckPosition tm;
				mo.CheckPosition(mo.pos.xy, true, tm);
				bActLikeBridge = oldBridge;
				if (tm.stepThing)
					continue; //Skip it
			}

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
	// GetUnlinkedPortal
	//============================
	private void GetUnlinkedPortal (bool forceRun = false)
	{
		if (lastGetUPTime == level.mapTime && !forceRun)
			return; //Already called in this tic
		lastGetUPTime = level.mapTime;

		//Our bounding box
		double size = radius + EXTRA_SIZE; //Pretend we're a bit bigger
		double minX1 = pos.x - size;
		double maxX1 = pos.x + size;
		double minY1 = pos.y - size;
		double maxY1 = pos.y + size;

		for (uint iPorts = nearbyUPorts.Size(); iPorts-- > 0;)
		{
			let port = nearbyUPorts[iPorts];
			if (!port.IsLinePortal()) //Make sure it's still a line portal
			{
				nearbyUPorts.Delete(iPorts);
				continue;
			}

			//Line bounding box.
			//Reference for order: https://github.com/uzdoom/uzdoom/blob/trunk/src/common/utility/m_bbox.h
			double minX2 = port.bbox[2]; //left
			double maxX2 = port.bbox[3]; //right
			double minY2 = port.bbox[1]; //bottom
			double maxY2 = port.bbox[0]; //top

			if (minX1 >= maxX2 || minX2 >= maxX1 ||
				minY1 >= maxY2 || minY2 >= maxY1)
			{
				continue; //BBoxes not intersecting
			}

			if (IsBehindLine(pos.xy, port))
				continue; //Center point not in front of line

			if (level.BoxOnLineSide(pos.xy, size, port) != -1)
				continue; //All corners on one side; there's no intersection with line

			if (lastUPort != port)
			{
				lastUPort = port;

				//Swap entries so next time 'lastUPort' is checked first
				uint lastIndex = nearbyUPorts.Size() - 1;
				nearbyUPorts[iPorts] = nearbyUPorts[lastIndex];
				nearbyUPorts[lastIndex] = port;
			}
			return;
		}
		lastUPort = null;
	}

	//============================
	// TranslatePortalVector
	//============================
	static vector3, double TranslatePortalVector (vector3 vec, Line port, bool isPos, bool backward)
	{
		Line dest;
		if (!port || !(dest = port.GetPortalDestination()))
			return vec, 0;

		int portAlignment = isPos ? port.GetPortalAlignment() : 0;
		double delta = port.GetPortalAngleDiff();

		if (backward)
		{
			//Swap them
			Line oldPort = port;
			port = dest;
			dest = oldPort;

			//If this is a portal, use its alignment. Else still use the other one's.
			if (port.IsLinePortal())
			{
				portAlignment = isPos ? port.GetPortalAlignment() : 0;
				delta = port.GetPortalAngleDiff();
			}
			else
			{
				delta = -delta;
			}
		}

		if (isPos)
			vec.xy -= port.v1.p;
		if (delta)
			vec.xy = RotateVector(vec.xy, delta);
		if (isPos)
			vec.xy += dest.v2.p;

		switch (portAlignment)
		{
			case LinePortal.PORG_FLOOR:
				vec.z += dest.frontSector.floorPlane.ZatPoint(dest.v2.p) - port.frontSector.floorPlane.ZatPoint(port.v1.p);
				break;
			case LinePortal.PORG_CEILING:
				vec.z += dest.frontSector.ceilingPlane.ZatPoint(dest.v2.p) - port.frontSector.ceilingPlane.ZatPoint(port.v1.p);
				break;
		}
		return vec, delta;
	}

	//============================
	// ExchangePassengersWithTwin
	//============================
	private void ExchangePassengersWithTwin ()
	{
		//This function is never called by the portal copy
		if (!portTwin || portTwin.portTwin != self)
			return;

		int myLastIndex = passengers.Size() - 1;
		int oldPortTwinLastIndex = portTwin.passengers.Size() - 1;

		for (int iTwins = 0; iTwins < 2; ++iTwins)
		{
			let plat = (iTwins == 0) ? self : portTwin;
			if (!plat)
				break;

			if (iTwins == 0 && portTwin.bNoBlockmap)
				continue; //Don't give anything to the portal copy if it's not in use

			for (int i = (iTwins == 0) ? myLastIndex : oldPortTwinLastIndex; i > -1; --i)
			{
				//If any of our passengers have passed through a portal,
				//check if they're on the twin's side of that portal.
				//If so, give them to our twin.
				let mo = plat.passengers[i];
				if (!mo || mo.bDestroyed)
				{
					plat.ForgetPassenger(i);
					continue;
				}

				if (plat.portTwin.passengers.Find(mo) >= plat.portTwin.passengers.Size() &&
					mo.Distance3D(plat.portTwin) < mo.Distance3D(plat))
				{
					let platPass = FishyPlatform(mo);
					if (platPass && platPass.group && platPass.group.carrier == plat)
						platPass.group.carrier = plat.portTwin;

					plat.passengers.Delete(i);
					plat.portTwin.passengers.Push(mo);
				}
			}
		}
	}

	//============================
	// UpdateOldInfo
	//============================
	private void UpdateOldInfo ()
	{
		oldPos = pos;
		oldAngle = angle;
		oldPitch = pitch;
		oldRoll = roll;
	}

	//============================
	// GoBack
	//============================
	private void GoBack (vector3 goPos = (double.nan, 0, 0), double goAngle = double.nan, double goPitch = double.nan, double goRoll = double.nan)
	{
		//Going back to our old position/angle/pitch/roll is what would usually happen
		if (goPos != goPos) //NaN check
			goPos = oldPos;

		if (pos != goPos)
			SetOrigin(goPos, true);

		angle = (goAngle == goAngle) ? goAngle : oldAngle;
		pitch = (goPitch == goPitch) ? goPitch : oldPitch;
		roll = (goRoll == goRoll) ? goRoll : oldRoll;
	}

	//============================
	// PlatTakeOneStep
	//============================
	private bool PlatTakeOneStep (vector3 newPos)
	{
		double startZ = pos.z;

		//The "invisible" portal twin (copy) isn't meant to go through portals.
		//Don't call TryMove() nor Vec3Offset() for it.
		SetZ(newPos.z);
		bool moved = bPortCopy ? FitsAtPosition(self, newPos) : TryMove(newPos.xy, 1);
		let mo = blockingMobj;

		//Remember 'blockingMobj' as a "nearby actor" if it isn't one already
		if (mo && nearbyActors.Find(mo) >= nearbyActors.Size())
			nearbyActors.Push(mo);

		if (!moved && mo)
		{
			let moOldZ = mo.pos.z;
			let moNewZ = newPos.z + self.height;

			//If we could carry it, try to set the obstacle on top of us
			//if its 'maxStepHeight' allows it.
			if (moNewZ > moOldZ && IsCarriable(mo) && moNewZ - moOldZ <= mo.maxStepHeight)
			{
				let plat = FishyPlatform(mo);
				if (plat)
				{
					//Try one more time - unlike in the lower case,
					//we won't move back 'plat' if the move failed again.
					if (plat.DoPlatZFix(moNewZ, self))
						moved = bPortCopy ? FitsAtPosition(self, newPos) : TryMove(newPos.xy, 1);
				}
				else
				{
					PassengerPreMove(mo);
					bool fits = FitsAtPosition(mo, (mo.pos.xy, moNewZ), true);
					if (fits)
					{
						mo.SetZ(moNewZ);

						//Try one more time
						moved = bPortCopy ? FitsAtPosition(self, newPos) : TryMove(newPos.xy, 1);
						if (!moved)
						{
							mo.SetZ(moOldZ);
							fits = false;
							blockingMobj = mo; //Needed for later; TryMove() might have nulled it
						}
						else
						{
							mo.CheckPortalTransition(); //Handle sector portals properly
						}
					}
					PassengerPostMove(mo, fits);
				}
			}
		}
		else if (!moved) //Blocked by geometry?
		{
			if (options & OPTFLAG_IGNOREGEO)
			{
				moved = true;
				if (!bPortCopy)
					SetOrigin(level.Vec3Offset(pos, newPos - pos), true);
			}
		}

		if (moved && bPortCopy)
		{
			SetOrigin(newPos, true);
		}
		else if (!moved)
		{
			SetZ(startZ);
			if (newPos.z < startZ)
			{
				//If an obstacle is below us and we're attempting to go down, try to stand on it
				let mo = blockingMobj;
				double moTop;
				if (mo && (moTop = mo.pos.z + mo.height) < startZ && OverlapXY(self, mo) && FitsAtPosition(self, (pos.xy, moTop)))
				{
					bOnMobj = true;
					SetZ(moTop);
					if (!bPortCopy)
						CheckPortalTransition(); //Handle sector portals properly

					//Self-note: No, we don't call MovePassengers() here.
					//With a straight-forward downward movement it's not needed.
					//It's not an issue if our passengers are floaters
					//or there's no gravity to move them downward.

					//Try to adjust our twin
					if (portTwin && (!portTwin.bNoBlockmap || !portTwin.bPortCopy))
					{
						double twinZ = portTwin.pos.z + moTop - startZ;
						if (portTwin.pos.z != twinZ && FitsAtPosition(portTwin, (portTwin.pos.xy, twinZ)))
						{
							portTwin.bOnMobj = true;
							portTwin.SetZ(twinZ);
							if (!portTwin.bPortCopy)
								portTwin.CheckPortalTransition(); //Handle sector portals properly
						}
					}
				}
			}
		}

		return moved;
	}

	//============================
	// GetStuckActors
	//============================
	private void GetStuckActors ()
	{
		//A slimmed down version of GetNewPassengers()
		//that only looks for stuck actors.
		for (uint iActors = nearbyActors.Size(); iActors-- > 0;)
		{
			let mo = nearbyActors[iActors];
			if (!mo || mo.bDestroyed)
			{
				nearbyActors.Delete(iActors);
				continue;
			}

			if (mo.bNoBlockmap)
				continue;

			if (SpecialBTIActor(mo))
				continue; //Already handled

			if (!CollisionFlagChecks(self, mo))
				continue;

			if (stuckActors.Find(mo) < stuckActors.Size())
				continue; //Already in the array

			let plat = FishyPlatform(mo);
			if (plat && (plat.bInMove || (plat.portTwin && plat.portTwin.bInMove) ) )
				continue; //This is likely the platform that carries us; ignore it

			if (!OverlapZ(self, mo) || !OverlapXY(self, mo))
				continue; //No overlap

			if (self.CanCollideWith(mo, false) && mo.CanCollideWith(self, true))
				stuckActors.Push(mo); //Got one
		}
	}

	//============================
	// HandleStuckActors
	//============================
	private void HandleStuckActors (bool doStandOn)
	{
		double top = pos.z + height;
		Actor highestMo = null;
		Array<Actor> delayedPush;
		bool fixedSome = false;
		bool doPush = bPushStuckActors; //Remember the value because DoPlatZFix() will set this to 'true'

		for (uint i = stuckActors.Size(); i-- > 0;)
		{
			let mo = stuckActors[i];
			if (!mo || mo.bDestroyed || //Thing_Remove()'d?
				!CollisionFlagChecks(self, mo) || //Non-solid?
				!OverlapZ(self, mo) || !OverlapXY(self, mo) || //No overlap?
				!self.CanCollideWith(mo, false) || !mo.CanCollideWith(self, true) ) //No collision?
			{
				stuckActors.Delete(i);
				continue;
			}

			if (IsCarriable(mo) && top - mo.pos.z <= mo.maxStepHeight)
			{
				bool fits;

				let plat = FishyPlatform(mo);
				if (plat)
				{
					fits = plat.DoPlatZFix(top, self);
				}
				else
				{
					PassengerPreMove(mo);
					fits = FitsAtPosition(mo, (mo.pos.xy, top), true);
					if (fits)
					{
						mo.SetZ(top);
						mo.CheckPortalTransition(); //Handle sector portals properly
					}
					PassengerPostMove(mo, fits);
				}

				if (fits)
				{
					stuckActors.Delete(i);
					fixedSome = true;
					continue;
				}
			}
			else if (!doStandOn && mo.player && mo.bFly && mo.pos.z < self.pos.z)
			{
				//I don't know why, but a flying player that moves with enough
				//horizontal velocity while also moving upwards can clip into us.
				//It's what caused an old bug where idle, nogravity platforms would get "pushed" upward.
				//Fixing *that* revealed this little quirk...
				//So take care of it by keeping flying players below us, if possible.
				double fixPlayerZ = self.pos.z - mo.height;
				if (FitsAtPosition(mo, (mo.pos.xy, fixPlayerZ)))
				{
					mo.SetZ(fixPlayerZ);
					mo.CheckPortalTransition(); //Handle sector portals properly
					//NOTE: it seems right to delete the array entry for "stuckActors" here, but, but, but!!!
					//For some stupid reason doing so makes the player viewbob behavior very jittery *if*
					//the player continues to fly upward!
					//That's why we're not deleting the array entry.
					continue;
				}
			}

			if (doStandOn && (!highestMo || highestMo.pos.z + highestMo.height < mo.pos.z + mo.height))
			{
				highestMo = mo;
				if (doPush)
					delayedPush.Push(mo);
			}
			else if (doPush)
			{
				PushObstacle(mo);
			}
		}

		//Try to stand on the highest stuck actor if our 'maxStepHeight' allows it
		double moTop;
		if (highestMo && (moTop = highestMo.pos.z + highestMo.height) - pos.z <= maxStepHeight)
		{
			if (fixedSome)
				GetNewPassengers(false);

			if (DoPlatZFix(moTop, self))
			{
				stuckActors.Delete(stuckActors.Find(highestMo));
				if (doPush)
					delayedPush.Delete(delayedPush.Find(highestMo));
			}
		}

		for (uint i = delayedPush.Size(); i-- > 0;)
			PushObstacle(delayedPush[i]);

		if (stuckActors.Size())
			bOnMobj = true;
	}

	//============================
	// PlatMove
	//============================
	private int PlatMove (vector3 newPos, double newAngle, double newPitch, double newRoll, PMoveTypes moveType)
	{
		// "Quick move" is used to correct the position/angles and it is assumed
		// that 'newPos/Angle/Pitch/Roll' is only marginally different from
		// the current position/angles.
		// "Quick move teleport" is for moving platforms back to where they were.

		FishyPlatform plat;
		if (group && group.origin != self)
			SetGroupOrigin(self);

		bool teleMove = (moveType == MOVE_TELEPORT || moveType == MOVE_TRUETELE);

		if (moveType != MOVE_TELEPORT)
			bPushStuckActors = true;

		if (moveType > MOVE_QUICK) //Not a quick move?
		for (int i = -1; i == -1 || (group && i < group.members.Size()); ++i)
		{
			plat = (i == -1) ? self : group.GetMember(i);
			if (i > -1 && (!plat || plat == self)) //Already handled self
				continue;

			//More often than not "teleport moves" involve warping to
			//our first interpolation point.
			//Or being moved by our group origin as soon as the map starts.
			//In such cases get everything that's around us now before
			//we actually move.
			if (teleMove)
				plat.GetNewBmapResults();

			if (moveType == MOVE_NORMAL || moveType == MOVE_REPEAT)
			{
				if (plat.bSearchForUPorts)
					plat.GetUnlinkedPortal();

				if (plat.lastUPort && !plat.portTwin)
				{
					//Create invisible portal twin to help with non-static line portal collision/physics
					plat.portTwin = FishyPlatform(Spawn(plat.GetClass(), TranslatePortalVector(plat.pos, plat.lastUPort, true, false)));
					plat.portTwin.portTwin = plat;
					plat.portTwin.bPortCopy = true;
					plat.portTwin.bInvisible = true;
				}
			}

			if (plat.portTwin)
			{
				//Take into account SetActorFlag() shenanigans.
				//For sanity's sake just copy some
				//of the flags that are defined in
				//the "default" block plus CANNOTPUSH, PUSHABLE
				//and NOFRICTION.
				//INTERPOLATEANGLES is a render flag so skip it.

				plat.portTwin.bActLikeBridge = plat.bActLikeBridge;
				plat.portTwin.bNoGravity = plat.bNoGravity;
				plat.portTwin.bNoFriction = plat.bNoFriction;
				plat.portTwin.bCanPass = plat.bCanPass;
				plat.portTwin.bSolid = plat.bSolid;
				plat.portTwin.bShootable = plat.bShootable;
				plat.portTwin.bBumpSpecial = plat.bBumpSpecial;
				plat.portTwin.bNoDamage = plat.bNoDamage;
				plat.portTwin.bNoBlood = plat.bNoBlood;
				plat.portTwin.bDontThrust = plat.bDontThrust;
				plat.portTwin.bNotAutoAimed = plat.bNotAutoAimed;
				plat.portTwin.bCannotPush = plat.bCannotPush;
				plat.portTwin.bPushable = plat.bPushable;
				if (plat.portTwin.radius != plat.radius || plat.portTwin.height != plat.height)
					plat.portTwin.A_SetSize(plat.radius, plat.height);
				plat.portTwin.options = plat.options;
				plat.portTwin.crushDamage = plat.crushDamage;
				plat.portTwin.bNoPassOrbit = plat.bNoPassOrbit;
				plat.portTwin.bNoCorpseGib = plat.bNoCorpseGib;
				plat.portTwin.special = plat.special;
				for (int i = 0; i < 5; ++i)
					plat.portTwin.args[i] = plat.args[i];

				if (plat.bPlatPorted)
				{
					plat.portTwin.bPlatPorted = true;
					plat.portTwin.platTeleFlags = plat.platTeleFlags;
				}

				if (plat.portTwin.bNoBlockmap && plat.lastUPort)
				{
					plat.portTwin.A_ChangeLinkFlags(YES_BMAP);
					plat.portTwin.SetOrigin(TranslatePortalVector(plat.pos, plat.lastUPort, true, false), true);
				}
				else if (!plat.portTwin.bNoBlockmap && !plat.lastUPort)
				{
					plat.portTwin.A_ChangeLinkFlags(NO_BMAP); //No collision while not needed (don't destroy it - not here)
				}

				if (teleMove)
					plat.portTwin.GetNewBmapResults();
			}

			if ((!plat.GetNewPassengers(moveType == MOVE_TELEPORT) ||
				(plat.portTwin && !plat.portTwin.bNoBlockmap &&
				!plat.portTwin.GetNewPassengers(moveType == MOVE_TELEPORT) ) ) && moveType != MOVE_REPEAT )
			{
				return 0; //GetNewPassengers() detected a stuck actor that couldn't be resolved
			}
		}

		if (moveType > MOVE_QUICK) //Not a quick move?
		for (int i = -1; i == -1 || (group && i < group.members.Size()); ++i)
		{
			plat = (i == -1) ? self : group.GetMember(i);
			if (i > -1 && (!plat || plat == self)) //Already handled self
				continue;

			for (int iTwins = 0; iTwins < 2; ++iTwins)
			{
				if (iTwins > 0 && !(plat = plat.portTwin))
					break;

				//Get all passengers that are platforms and call their GetNewPassengers() now.
				//That should allow them to take some of our other passengers.
				for (uint iPass = plat.passengers.Size(); iPass-- > 0;)
				{
					let platPass = FishyPlatform(plat.passengers[iPass]);
					if (!platPass || platPass.bNoBlockmap) //They shouldn't have NOBLOCKMAP now - this is taken care of below
						continue;

					if (teleMove)
						platPass.GetNewBmapResults();
					platPass.GetNewPassengers(moveType == MOVE_TELEPORT);

					//If passengers get stolen the array size will shrink
					//and this one's position in the array might have changed.
					//So take that into account.
					iPass = plat.passengers.Find(platPass);
				}
			}
		}

		for (int i = -1; i == -1 || (group && i < group.members.Size()); ++i)
		{
			plat = (i == -1) ? self : group.GetMember(i);
			if (i > -1 && (!plat || plat == self)) //Already handled self
				continue;

			plat.bMoved = false;
			plat.bInMove = true;

			if (group && group.origin && (group.origin.options & OPTFLAG_DIFFPASSCOLL))
				plat.UnlinkPassengers();
		}

		int result = DoMove(newPos, newAngle, newPitch, newRoll, moveType) ? 1 : 0;
		if (result)
			result = (!group || MoveGroup(moveType)) ? 2 : 1;

		for (int i = -1; i == -1 || (group && i < group.members.Size()); ++i)
		{
			plat = (i == -1) ? self : group.GetMember(i);
			if (i > -1 && (!plat || plat == self)) //Already handled self
				continue;

			plat.bInMove = false;

			if (group && group.origin && (group.origin.options & OPTFLAG_DIFFPASSCOLL))
				plat.LinkPassengers(plat.bMoved);
		}
		return result;
	}

	//============================
	// DoMove
	//============================
	private bool DoMove (vector3 newPos, double newAngle, double newPitch, double newRoll, PMoveTypes moveType)
	{
		if (pos == newPos && angle == newAngle && pitch == newPitch && roll == newRoll)
			return true;

		vector3 startPos = pos;
		double startAngle = angle;
		double startPitch = pitch;
		double startRoll = roll;

		double delta, piDelta, roDelta;
		if (moveType != MOVE_NORMAL || pos == newPos)
		{
			if (moveType == MOVE_TRUETELE)
			{
				//Handle this early in case something goes wrong
				if (!Teleport(newPos, newAngle, platTeleFlags))
					return false;

				if (bDestroyed)
					return true; //Because we technically made a move before being destroyed

				CheckPortalTransition(); //Handle sector portals properly
				newPos = pos; //Don't let CheckPortalTransition() confuse the (pos != newPos) if condition below
				moveType = MOVE_QUICKTELE;
			}

			angle = newAngle;
			pitch = newPitch;
			roll = newRoll;

			//For MovePassengers()
			delta = DeltaAngle(startAngle, newAngle);
			piDelta = (moveType == MOVE_TELEPORT) ? 0 : DeltaAngle(startPitch, newPitch);
			roDelta = (moveType == MOVE_TELEPORT) ? 0 : DeltaAngle(startRoll, newRoll);

			if (lastUPort)
			{
				double angDiff;
				[portTwin.oldPos, angDiff] = TranslatePortalVector(startPos, lastUPort, true, false);
				portTwin.angle = newAngle + angDiff;

				if (startPos != newPos)
					portTwin.SetOrigin(TranslatePortalVector(newPos, lastUPort, true, false), true);
				else if (portTwin.oldPos != portTwin.pos)
					portTwin.SetOrigin(portTwin.oldPos, true);
			}
		}

		if (moveType <= MOVE_QUICK || moveType == MOVE_REPEAT)
		{
			if (pos != newPos)
			{
				SetOrigin(newPos, true);
				let oldPrev = prev;
				CheckPortalTransition(); //Handle sector portals properly
				prev = oldPrev;
			}

			bool telePass = (moveType == MOVE_QUICKTELE);

			MovePassengers(startPos, pos, angle, delta, piDelta, roDelta, telePass);
			if (lastUPort)
				portTwin.MovePassengers(portTwin.oldPos, portTwin.pos, portTwin.angle, delta, piDelta, roDelta, telePass);
			ExchangePassengersWithTwin();

			bMoved = true;
			return true;
		}

		if (moveType == MOVE_TELEPORT || pos == newPos)
		{
			if (pos != newPos)
			{
				SetOrigin(newPos, false);
				CheckPortalTransition(); //Handle sector portals properly
			}

			bool result = true;
			bool telePass = (moveType == MOVE_TELEPORT);
			bool movedMine = MovePassengers(startPos, pos, angle, delta, piDelta, roDelta, telePass);

			if (!movedMine || (lastUPort &&
				!portTwin.MovePassengers(portTwin.oldPos, portTwin.pos, portTwin.angle, delta, piDelta, roDelta, telePass) ) )
			{
				if (movedMine)
					MovePassengers(pos, startPos, angle, -delta, -piDelta, -roDelta, true); //Move them back

				GoBack(startPos, startAngle, startPitch, startRoll);
				if (lastUPort)
					portTwin.GoBack();
				result = false;
			}
			else if (lastUPort)
			{
				ExchangePassengersWithTwin();
			}

			bMoved = result;
			return result;
		}

		int maxSteps = 1;
		vector3 stepMove = level.Vec3Diff(pos, newPos);
		vector3 pushForce = stepMove;

		//If the move is equal or larger than our radius
		//then it has to be split up into smaller steps.
		//This is needed for proper collision.
		//NOTE: This was based on similar code from P_XYMovement().
		double maxMove = max(1, radius - 1);
		double moveSpeed = max(abs(stepMove.x), abs(stepMove.y));
		if (moveSpeed > maxMove)
		{
			maxSteps = int(1 + moveSpeed / maxMove);
			stepMove /= maxSteps;
		}

		for (int step = 0; step < maxSteps; ++step)
		{
			let oldPGroup = curSector.portalGroup;
			startPos = pos;
			startAngle = angle;
			startPitch = pitch;
			startRoll = roll;
			newPos = pos + stepMove;
			if (!PlatTakeOneStep(newPos))
			{
				if (blockingMobj)
				{
					let mo = blockingMobj;
					if (portTwin && !portTwin.bNoBlockmap && lastUPort &&
						mo.Distance3D(portTwin) < mo.Distance3D(self))
					{
						portTwin.PushObstacle(mo, TranslatePortalVector(pushForce, lastUPort, false, false));
					}
					else
					{
						PushObstacle(mo, pushForce);
					}
				}
				return false;
			}

			if (!bPlatPorted && //Not triggered a teleport special? (That's not teleport-to-line)
				newPos.xy != pos.xy && //And yet the position is not what was expected?
				!lastUPort && //We weren't touching an unlinked line portal before taking a step?
				curSector.portalGroup == oldPGroup) //We did not cross a linked/static line portal?
			{
				//Assume we activated a teleport-to-line special
				bPlatPorted = true;
				platTeleFlags = 0;
			}

			if (bPlatPorted) //Did we activate a teleport special?
			{
				//Keep it simple
				newPos = pos;
				newAngle = angle;
				portDelta += DeltaAngle(startAngle, angle); //For SetInterpolationCoordinates()
				GoBack(startPos, startAngle, startPitch, startRoll);
				return DoMove(newPos, newAngle, newPitch, newRoll, MOVE_QUICKTELE);
			}

			//For MovePassengers().
			//Any portal induced angle changes
			//should not affect passenger rotation.
			vector3 portalAwareStartPos = startPos;
			delta = (step > 0) ? 0 : DeltaAngle(startAngle, newAngle);
			piDelta = (step > 0) ? 0 : DeltaAngle(startPitch, newPitch);
			roDelta = (step > 0) ? 0 : DeltaAngle(startRoll, newRoll);

			double angDiff;
			if (newPos.xy != pos.xy)
			{
				//If we have passed through a (non-static) portal
				//then adjust a few things.
				portalAwareStartPos -= newPos;
				angDiff = DeltaAngle(startAngle, angle);
				if (angDiff)
				{
					portDelta += angDiff; //For SetInterpolationCoordinates()
					portalAwareStartPos.xy = RotateVector(portalAwareStartPos.xy, angDiff);

					if (step == 0)
						newAngle += angDiff;

					if (step < maxSteps - 1)
						stepMove.xy = RotateVector(stepMove.xy, angDiff);
				}
				portalAwareStartPos += pos;
			}

			if (step == 0)
			{
				angle = newAngle;
				pitch = newPitch;
				roll = newRoll;
			}

			bool crossedPortal = false;
			if (lastUPort)
			{
				vector3 twinPos;
				if (newPos.xy == pos.xy)
				{
					[portTwin.oldPos, angDiff] = TranslatePortalVector(startPos, lastUPort, true, false);
					portTwin.angle = angle + angDiff;
					twinPos = TranslatePortalVector(pos, lastUPort, true, false);
				}
				else
				{
					portTwin.oldPos = startPos;
					portTwin.angle = angle - angDiff;
					twinPos = newPos;
					angDiff = 0;
				}

				bool moved = portTwin.PlatTakeOneStep(twinPos);
				if (moved && newPos.xy != pos.xy)
				{
					crossedPortal = true;
					ExchangePassengersWithTwin();
				}
				else if (!moved)
				{
					GoBack(startPos, startAngle, startPitch, startRoll);
					if (portTwin.blockingMobj)
					{
						vector3 twinPushForce = pushForce;
						if (angDiff)
							twinPushForce.xy = RotateVector(twinPushForce.xy, angDiff);
						portTwin.PushObstacle(portTwin.blockingMobj, twinPushForce);
					}
					return false;
				}
			}

			bool movedMine = MovePassengers(portalAwareStartPos, pos, angle, delta, piDelta, roDelta, false);
			if (!movedMine || (lastUPort &&
				!portTwin.MovePassengers(portTwin.oldPos, portTwin.pos, portTwin.angle, delta, piDelta, roDelta, false) ) )
			{
				if (movedMine)
					MovePassengers(pos, portalAwareStartPos, angle, -delta, -piDelta, -roDelta, true); //Move them back

				GoBack(startPos, startAngle, startPitch, startRoll);
				if (lastUPort)
					portTwin.GoBack();
				return false;
			}

			ExchangePassengersWithTwin();
			CheckPortalTransition(); //Handle sector portals properly
			if (crossedPortal && bSearchForUPorts && step < maxSteps - 1)
			{
				GetNewBmapResults(true);
				GetUnlinkedPortal(true);
			}
			bMoved = true;
		}
		return true;
	}

	//============================
	// MoveGroup
	//============================
	private bool MoveGroup (PMoveTypes moveType)
	{
		if (bPlatPorted)
			moveType = MOVE_TRUETELE;

		double delta = double.nan;
		double piDelta = double.nan;
		double roDelta = double.nan;
		vector3 mirOfs = (double.nan, 0, 0);
		quat qRot = quat(double.nan, 0, 0, 0);

		for (int iPlat = 0; iPlat < group.members.Size(); ++iPlat)
		{
			let plat = group.GetMember(iPlat);
			if (!plat || plat == self)
				continue;

			bool changeAng = (plat.options & OPTFLAG_ANGLE);
			bool changePi = (plat.options & OPTFLAG_PITCH);
			bool changeRo = (plat.options & OPTFLAG_ROLL);

			vector3 newPos;
			double newAngle = plat.angle;
			double newPitch = plat.pitch;
			double newRoll = plat.roll;

			if (plat.options & OPTFLAG_MIRROR)
			{
				//The way we mirror movement is by getting the offset going
				//from the origin's current position to its 'groupMirrorPos'
				//and using that to get a offsetted position from
				//the attached platform's 'groupMirrorPos'.
				//So we pretty much always go in the opposite direction
				//using 'groupMirrorPos' as a reference point.
				if (mirOfs != mirOfs) //NaN check
					mirOfs = level.Vec3Diff(pos, groupMirrorPos);
				newPos = level.Vec3Offset(plat.groupMirrorPos, mirOfs);

				if (changeAng)
				{
					if (delta != delta) //NaN check
						delta = DeltaAngle(angle, groupAngle);
					newAngle = plat.groupAngle + delta;
				}
				if (changePi)
				{
					if (piDelta != piDelta) //NaN check
						piDelta = DeltaAngle(pitch, groupPitch);
					newPitch = plat.groupPitch + piDelta;
				}
				if (changeRo)
				{
					if (roDelta != roDelta) //NaN check
						roDelta = DeltaAngle(roll, groupRoll);
					newRoll = plat.groupRoll + roDelta;
				}
			}
			else //Non-mirror movement. Rotation happens here.
			{
				if (qRot != qRot) //NaN check
					qRot = quat.FromAngles(angle, pitch, roll);
				newPos = level.Vec3Offset(pos, qRot * plat.groupRotOffset);

				if (changeAng || changePi || changeRo)
				{
					let [qYaw, qPitch, qRoll, atPole] = AnglesFromQuat(qRot * plat.groupRotAngDiff);

					//When the quat-to-euler angles cross the north/south pole,
					//the yaw/roll difference is suddenly 180 degrees.
					//This causes the render interpolation to visibly "glitch"
					//and passengers get flung around in unexpected ways.
					//To handle that, we set the angles right here then clear interpolations.
					//
					//This will affect MovePassengers() so yaw/pitch/roll changes
					//don't influence passenger movement; this is intentional.

					bool extremeQuatAngDiff = (plat.bQuatAngsAtPole != atPole);
					plat.bQuatAngsAtPole = atPole;

					if (changeAng)
					{
						newAngle = qYaw;
						if (extremeQuatAngDiff)
							plat.angle = qYaw;
					}
					if (changePi)
					{
						newPitch = qPitch;
						if (extremeQuatAngDiff)
							plat.pitch = qPitch;
					}
					if (changeRo)
					{
						newRoll = qRoll;
						if (extremeQuatAngDiff)
							plat.roll = qRoll;
					}
					if (extremeQuatAngDiff)
						plat.ClearInterpolation();
				}
			}

			if (bPlatPorted)
			{
				plat.bPlatPorted = true;
				plat.platTeleFlags = platTeleFlags;
			}

			if (!plat.DoMove(newPos, newAngle, newPitch, newRoll, moveType) && moveType > MOVE_QUICK)
				return false;
		}
		return true;
	}

	//============================
	// DoPlatZFix
	//============================
	private bool DoPlatZFix (double newZ, FishyPlatform mover)
	{
		// In most cases, this is called by other platforms to do
		// quick Z position corrections on potential platform passengers.
		// This isn't meant as a typical movement routine.
		// 
		// Keep in mind the position checks done here ignore actors on purpose.
		// We only care about geometry.

		double zOff = newZ - pos.z;
		if (bPortCopy)
			return portTwin.DoPlatZFix(portTwin.pos.z + zOff, mover); //Let the non-copy handle it

		if (group)
		{
			if (group.lastZFixTime == level.mapTime)
				return false; //Already called in this tic for this group
			group.lastZFixTime = level.mapTime;
		}

		bPushStuckActors = true;

		//We're going to try moving the entire group and everyone's passengers
		for (int i = -1; i == -1 || (group && i < group.members.Size()); ++i)
		{
			let plat = (i == -1) ? self : group.GetMember(i);
			if (i > -1 && (!plat || plat == self)) //Already handled self
				continue;

			for (int iTwins = 0; iTwins < 2; ++iTwins)
			{
				if (iTwins > 0 && !(plat = plat.portTwin))
					break;

				//First move this platform
				newZ = plat.pos.z + zOff;

				//If we are the mover then don't treat self or our groupmates as passengers
				if (mover != self)
					mover.PassengerPreMove(plat);

				bool fits = FitsAtPosition(plat, (plat.pos.xy, newZ), true);
				if (fits)
				{
					let savedPos = plat.pos.xy;
					plat.SetZ(newZ);
					plat.CheckPortalTransition(); //Handle sector portals properly
					if (plat.bFollowingPath)
					{
						plat.pCurr.z += zOff;
						if (savedPos != plat.pos.xy) //Crossed a sector portal?
							plat.AdjustInterpolationCoordinates((savedPos, plat.pos.z), plat.pos, 0);
					}
				}

				if (mover != self)
					mover.PassengerPostMove(plat, fits);

				//We only care if self fits or not
				if (plat == self && !fits)
					return false; //If it doesn't fit, abort the whole thing

				//If we're the mover then each platform in the group
				//moves their own passengers. If we're not the mover
				//then said mover is responsible for moving them.
				let passMover = (mover != self) ? mover : plat;

				//Now move the platform's passengers
				for (uint iPass = plat.passengers.Size(); iPass-- > 0;)
				{
					let mo = plat.passengers[iPass];
					if (!mo || mo.bDestroyed)
						continue;

					newZ = mo.pos.z + zOff;
					let platPass = FishyPlatform(mo);
					if (platPass)
					{
						platPass.DoPlatZFix(newZ, passMover);
						continue;
					}

					passMover.PassengerPreMove(mo);

					fits = FitsAtPosition(mo, (mo.pos.xy, newZ), true);
					if (fits)
					{
						mo.SetZ(newZ);
						mo.CheckPortalTransition(); //Handle sector portals properly
					}

					passMover.PassengerPostMove(mo, fits);
				}
			}
		}
		return true;
	}

	//============================
	// Lerp
	//============================
	double Lerp (double p1, double p2)
	{
		return (p1 ~== p2) ? p1 : (p1 + time * (p2 - p1));
	}

	//============================
	// Splerp
	//============================
	double Splerp (double p1, double p2, double p3, double p4, bool isAngle = false)
	{
		//With angles it's enough that "current" (p2) and "next" (p3) are approximately the same
		//in which case the other two points that influence the spline will be completely ignored.
		//(It just looks bad otherwise.)
		if (isAngle)
		{
			if (p2 ~== p3)
				return p2;
		}
		else //World coordinate
		{
			if (p1 ~== p2 && p2 ~== p3 && p2 ~== p4)
				return p2;
		}

		// This was copy-pasted from PathFollower's Splerp() function
		//
		// Interpolate between p2 and p3 along a Catmull-Rom spline
		// http://research.microsoft.com/~hollasch/cgindex/curves/catmull-rom.html
		//
		// NOTE: the above link doesn't seem to work so here's an alternative. -Fishytza
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
	// SetPivot
	//============================
	void SetPivot (vector3 pivot, bool attach)
	{
		bPivotVectorIsPosition = !attach;
		if (bPivotVectorIsPosition)
		{
			pivotVector = pos + level.Vec3Diff(pos, pivot);
		}
		else
		{
			quat q = quat.FromAngles(angle, pitch, roll);
			pivotVector = q.Inverse() * level.Vec3Diff(pivot, pos);
		}
	}

	//============================
	// GetPivotedPosition
	//============================
	private vector3 GetPivotedPosition (vector3 givenPos, vector3 fromAngs, vector3 toAngs)
	{
		if (bPivotVectorIsPosition)
		{
			quat qRot = quat.FromAngles(fromAngs.x, fromAngs.y, fromAngs.z); //Where X is yaw, Y is pitch, and Z is roll
			vector3 offset = qRot.Inverse() * (givenPos - pivotVector); //Deliberate portal-ignorance here; portal-awareness is handled elsewhere
			qRot = quat.FromAngles(toAngs.x, toAngs.y, toAngs.z);
			offset = qRot * offset;
			givenPos = pivotVector + offset;
		}
		else if (pivotVector != (0, 0, 0)) //Is non-zero offset?
		{
			givenPos -= quat.FromAngles(fromAngs.x, fromAngs.y, fromAngs.z) * pivotVector;
			givenPos += quat.FromAngles(toAngs.x, toAngs.y, toAngs.z) * pivotVector;
		}
		return givenPos;
	}

	//============================
	// Interpolate
	//============================
	private bool, bool Interpolate (PMoveTypes moveType = MOVE_NORMAL)
	{
		//A heavily modified version of the
		//original function from PathFollower.

		//First boolean returns "false" if we ended up destroyed.
		//Second boolean returns "true" if this particular call moved us.

		bool linear = (options & OPTFLAG_LINEAR);
		bool changeAng = ((options | acsFlags) & OPTFLAG_ANGLE);
		bool changePi  = ((options | acsFlags) & OPTFLAG_PITCH);
		bool changeRo  = ((options | acsFlags) & OPTFLAG_ROLL);
		bool faceMove = (options & OPTFLAG_FACEMOVE);

		Vector3 dpos = (0, 0, 0);
		if (faceMove && time > 0)
			dpos = pos;

		vector3 startPos = pos;
		double startAngle = angle;
		double startPitch = pitch;
		double startRoll = roll;

		vector3 newPos;
		double newAngle = (!changeAng && user_turnspeed_angle_onpath) ? (angle + user_turnspeed_angle_onpath) % 360 : angle;
		double newPitch = (!changePi && user_turnspeed_pitch_onpath)  ? (pitch + user_turnspeed_pitch_onpath) % 360 : pitch;
		double newRoll  = (!changeRo && user_turnspeed_roll_onpath)   ? (roll + user_turnspeed_roll_onpath) % 360   : roll;

		if (linear)
		{
			newPos.x = Lerp(pCurr.x, pNext.x);
			newPos.y = Lerp(pCurr.y, pNext.y);
			newPos.z = Lerp(pCurr.z, pNext.z);
		}
		else //Spline
		{
			newPos.x = Splerp(pPrev.x, pCurr.x, pNext.x, pLast.x);
			newPos.y = Splerp(pPrev.y, pCurr.y, pNext.y, pLast.y);
			newPos.z = Splerp(pPrev.z, pCurr.z, pNext.z, pLast.z);
		}

		if (faceMove && changeRo)
			newRoll = 0; //Adjust roll

		if (faceMove && (changeAng || changePi))
		{
			if (linear)
			{
				dpos = pNext - pCurr;
			}
			else if (time > 0) //Spline
			{
				dpos = newPos - dpos;
			}
			else //Spline but with time <= 0
			{
				dpos = newPos;
				time = timeFrac;
				newPos.x = Splerp(pPrev.x, pCurr.x, pNext.x, pLast.x);
				newPos.y = Splerp(pPrev.y, pCurr.y, pNext.y, pLast.y);
				newPos.z = Splerp(pPrev.z, pCurr.z, pNext.z, pLast.z);
				time = 0;
				dpos = newPos - dpos;
				newPos -= dpos;
			}

			//Adjust angle
			if (changeAng)
				newAngle = VectorAngle(dpos.x, dpos.y);

			//Adjust pitch
			if (changePi)
			{
				double dist = dpos.xy.Length();
				newPitch = dist ? VectorAngle(dist, -dpos.z) : 0;
			}
		}

		if (!faceMove)
		{
			if (linear)
			{
				//Interpolate angle
				if (changeAng)
					newAngle = Lerp(pCurrAngs.x, pNextAngs.x);

				//Interpolate pitch
				if (changePi)
					newPitch = Lerp(pCurrAngs.y, pNextAngs.y);

				//Interpolate roll
				if (changeRo)
					newRoll = Lerp(pCurrAngs.z, pNextAngs.z);
			}
			else //Spline
			{
				//Interpolate angle
				if (changeAng)
					newAngle = Splerp(pPrevAngs.x, pCurrAngs.x, pNextAngs.x, pLastAngs.x, true);

				//Interpolate pitch
				if (changePi)
					newPitch = Splerp(pPrevAngs.y, pCurrAngs.y, pNextAngs.y, pLastAngs.y, true);

				//Interpolate roll
				if (changeRo)
					newRoll = Splerp(pPrevAngs.z, pCurrAngs.z, pNextAngs.z, pLastAngs.z, true);
			}
		}

		vector3 pivotAdjustedPos = newPos + interpolatedPivotOffset;
		if (!bIgnorePivot && (angle != newAngle || pitch != newPitch || roll != newRoll))
			pivotAdjustedPos = GetPivotedPosition(pivotAdjustedPos, (angle, pitch, roll), (newAngle, newPitch, newRoll));

		//Result == 2 means everyone moved. 1 == this platform moved but not all its groupmates moved.
		//(If this platform isn't in a group then the result is likewise 2 if it moved.)
		int result = PlatMove(pivotAdjustedPos, newAngle, newPitch, newRoll, moveType);
		if (bDestroyed)
			return false, (result == 2); //Abort if we ended up being Thing_Remove()'d

		if (result == 2)
		{
			interpolatedPivotOffset = pivotAdjustedPos - newPos;

			//This must be "true" for any amount of Interpolate() calls that have moved us
			//before the next HandleNonPathTurnSpeeds() call.
			//Multiple Interpolate() calls are possible through ACS.
			bInterpolateSuccess = true;
		}

		if (result == 2 && pos != pivotAdjustedPos) //Crossed a portal?
			AdjustInterpolationCoordinates(pivotAdjustedPos, pos, DeltaAngle(newAngle, angle));
		else if (result == 1)
			PlatMove(startPos, startAngle, startPitch, startRoll, MOVE_QUICKTELE); //Move the group back

		return (!bDestroyed), (result == 2);
	}

	//============================
	// HandleNonPathTurnSpeeds
	//============================
	private bool HandleNonPathTurnSpeeds ()
	{
		//Returns "false" if we got destroyed

		vector3 startPos = pos;
		double startAngle = angle;
		double startPitch = pitch;
		double startRoll = roll;

		bool gotVel = (vel != (0, 0, 0) && vel.LengthSquared() > MISCUSERVAR_LOWVEL);
		double turnSpeedAngle = (gotVel) ? user_turnspeed_angle_withvel : user_turnspeed_angle_idle;
		double turnSpeedPitch = (gotVel) ? user_turnspeed_pitch_withvel : user_turnspeed_pitch_idle;
		double turnSpeedRoll  = (gotVel) ? user_turnspeed_roll_withvel  : user_turnspeed_roll_idle;

		double newAngle = (turnSpeedAngle) ? (angle + turnSpeedAngle) % 360 : angle;
		double newPitch = (turnSpeedPitch) ? (pitch + turnSpeedPitch) % 360 : pitch;
		double newRoll  = (turnSpeedRoll)  ? (roll + turnSpeedRoll) % 360   : roll;

		//Hypothetically, this is the current interpolated position
		//that's unaffected by the pivot offset.
		vector3 pathPos = pos - interpolatedPivotOffset; //Don't call Lerp() or Splerp() for this

		vector3 pivotAdjustedPos = pos;
		if (!bIgnorePivot && (angle != newAngle || pitch != newPitch || roll != newRoll))
			pivotAdjustedPos = GetPivotedPosition(pivotAdjustedPos, (angle, pitch, roll), (newAngle, newPitch, newRoll));

		int result = PlatMove(pivotAdjustedPos, newAngle, newPitch, newRoll, MOVE_NORMAL);
		if (bDestroyed)
			return false; //Abort if we ended up being Thing_Remove()'d

		if (result == 2)
			interpolatedPivotOffset = pivotAdjustedPos - pathPos;

		if (result == 2 && pos != pivotAdjustedPos) //Crossed a portal?
			AdjustInterpolationCoordinates(pivotAdjustedPos, pos, DeltaAngle(newAngle, angle));
		else if (result == 1)
			PlatMove(startPos, startAngle, startPitch, startRoll, MOVE_QUICKTELE); //Move the group back

		return (!bDestroyed);
	}

	//============================
	// CallNodeSpecials
	//============================
	private bool CallNodeSpecials ()
	{
		let it = level.CreateActorIterator(currNode.tid, "InterpolationSpecial");
		Actor spec;

		//Precaution against Thing_Remove() shenanigans.
		//If a special holder gets removed/destroyed
		//during iteration then the iterator gets
		//messed up. Gather all specials before
		//calling them.
		Array<int> specList;
		while (spec = it.Next())
		{
			if (!spec.special)
				continue;
			specList.Push(spec.special);
			for (int i = 0; i < 5; ++i)
				specList.Push(spec.args[i]);
		}

		//Platform will be the activator of each special
		for (int i = specList.Size() - 1; i > -1; i -= 6)
			level.ExecuteSpecial(specList[i-5], self, null, false, specList[i-4], specList[i-3], specList[i-2], specList[i-1], specList[i]);

		return (!bDestroyed);
	}

	//============================
	// Deactivate (override)
	//============================
	override void Deactivate (Actor activator)
	{
		if (!bFollowingPath || bPortCopy)
			return;

		vel = (0, 0, 0);

		if (!group || !group.origin || group.origin == self)
		for (int i = -1; i == -1 || (group && group.origin == self && i < group.members.Size()); ++i)
		{
			let plat = (i == -1) ? self : group.GetMember(i);
			if (i > -1 && (!plat || plat == self)) //Already handled self
				continue;

			if (time <= 1.0) //Not reached destination?
				plat.Stopped(plat.oldPos, plat.pos);

			if (plat.portTwin && plat.portTwin.bNoBlockmap && plat.portTwin.bPortCopy)
				plat.portTwin.Destroy();
		}
		bFollowingPath = false;
	}

	//============================
	// Activate (override)
	//============================
	override void Activate (Actor activator)
	{
		if (!bFollowingPath || (group && group.origin != self))
		{
			if (bPortCopy)
				return;

			vel = (0, 0, 0);

			if (portTwin)
				portTwin.bFollowingPath = false;

			bRanActivationRoutine = true;
			if ((options & OPTFLAG_RESUMEPATH) && time <= 1.0)
			{
				bFollowingPath = true;
				if (group && group.origin != self)
					SetGroupOrigin(self, setNonOriginNoFollow: true);
				MustGetNewPassengers(); //Ignore search tic rate; do a search now
				return;
			}

			currNode = firstNode;
			prevNode = firstPrevNode;

			if (currNode)
			{
				portDelta = 0;
				acsFlags = 0;

				bGoToNode = (options & OPTFLAG_GOTONODE);
				if (!bGoToNode) //Don't call specials if going to 'currNode'
				{
					if (!CallNodeSpecials() || !currNode || currNode.bDestroyed)
						return; //Abort if we or the node got Thing_Remove()'d
				}
				bFollowingPath = true;
				if (group && group.origin != self)
					SetGroupOrigin(self, setNonOriginNoFollow: true);

				if (!bGoToNode)
				{
					let platNode = FishyPlatformNode(currNode);
					vector3 newPos = !platNode ? currNode.pos :
						platNode.FilterNoPosChange(noChange: pos, yesChange: currNode.pos);
					double newAngle = (options & OPTFLAG_ANGLE) ? currNode.angle : angle;
					double newPitch = (options & OPTFLAG_PITCH) ? currNode.pitch : pitch;
					double newRoll = (options & OPTFLAG_ROLL) ? currNode.roll : roll;
					PlatMove(newPos, newAngle, newPitch, newRoll, MOVE_TELEPORT);
				}
				else
				{
					MustGetNewPassengers(); //Ignore search tic rate; do a search now
				}

				vector3 startAngs = (bGoToNode ? angle : currNode.angle,
					bGoToNode ? pitch : currNode.pitch,
					bGoToNode ? roll : currNode.roll);
				SetInterpolationCoordinates(pos, startAngs);
				interpolatedPivotOffset = (0, 0, 0);
				SetTimeFraction();
				SetHoldTime();
				time = 0;
				reachedTime = 0;
				bTimeAlreadySet = true;
			}
		}
	}

	//============================
	// Stopped
	//============================
	private void Stopped (vector3 startPos, vector3 endPos)
	{
		if (!(options & OPTFLAG_ADDVELSTOP))
			return;

		vector3 pushForce = (double.nan, 0, 0); //No passengers == don't call level.Vec3Diff()

		for (int iTwins = 0; iTwins < 2; ++iTwins)
		{
			let plat = (iTwins == 0) ? self : portTwin;
			if (!plat || (iTwins > 0 && plat.bNoBlockmap))
				break;

			int lastIndex = plat.passengers.Size() - 1;
			if (lastIndex > -1)
			{
				if (pushForce != pushForce) //NaN check
					pushForce = level.Vec3Diff(startPos, endPos);

				if (iTwins > 0 && lastUPort)
					pushForce = TranslatePortalVector(pushForce, lastUPort, false, false);

				for (int i = lastIndex; i > -1; --i)
				{
					let mo = plat.passengers[i];
					if (!mo || mo.bDestroyed)
						plat.ForgetPassenger(i);
					else
						mo.vel += pushForce;
				}
			}
		}
	}

	//============================
	// PlatVelMove
	//============================
	private bool PlatVelMove ()
	{
		//Returns "false" if we end up destroyed

		//Handles velocity based movement (from being pushed around)
		vector3 startVel = vel;

		//Apparently slamming into the floor/ceiling doesn't
		//count as a cancelled move so take care of that.
		if ((vel.z < 0 && pos.z <= floorZ) ||
			(vel.z > 0 && pos.z + height >= ceilingZ))
		{
			if (!(options & OPTFLAG_IGNOREGEO))
				vel.z = 0;
		}

		if (vel == (0, 0, 0))
		{
			if (startVel.z != 0)
				bUserSoundsShouldMove = true; //Play "blocked" sound
			return true; //Nothing else to do here
		}

		double startAngle = angle;
		vector3 startPos = pos;
		vector3 newPos = pos + vel;
		int result = PlatMove(newPos, angle, pitch, roll, MOVE_NORMAL);
		if (bDestroyed)
			return false; //Abort if we got Thing_Remove()'d

		if (result != 2)
		{
			//Check if it's a culprit that blocks XY movement
			if (!vel.z || blockingLine || (blockingMobj && !OverlapXY(self, blockingMobj)))
			{
				vel = (0, 0, 0);
			}
			else
			{
				//Try again but without the Z component
				vel.z = 0;
				newPos.z = startPos.z;
				if (vel.xy == (0, 0) || (result = PlatMove(newPos, angle, pitch, roll, MOVE_NORMAL)) != 2)
				{
					if (bDestroyed)
						return false; //Abort if we got Thing_Remove()'d
					vel = (0, 0, 0);
				}
			}
		}

		if (result == 2 && bFollowingPath)
		{
			pCurr += vel;
			if (pos != newPos) //Crossed a portal?
				AdjustInterpolationCoordinates(newPos, pos, DeltaAngle(startAngle, angle));
		}
		else if (result == 1) //This platform has moved, but one or all of its groupmates hasn't
		{
			PlatMove(startPos, startAngle, pitch, roll, MOVE_QUICKTELE); //...So move them back
		}

		if (vel == (0, 0, 0) && startVel != (0, 0, 0))
			bUserSoundsShouldMove = true; //Play "blocked" sound

		return (!bDestroyed);
	}

	//============================
	// PostTeleport (override)
	//============================
	override void PostTeleport (vector3 destPos, double destAngle, int flags)
	{
		bPlatPorted = true;
		platTeleFlags = flags;
	}

	//============================
	// MarkPrecacheSounds (override)
	//============================
	override void MarkPrecacheSounds ()
	{
		Super.MarkPrecacheSounds();
		MarkSound(user_snd_start);
		MarkSound(user_snd_stop);
		MarkSound(user_snd_blocked);
		MarkSound(user_snd_move);
	}

	//============================
	// CheckUserSoundsMovement
	//============================
	private bool, bool CheckUserSoundsMovement ()
	{
		bool shouldMove = (
			(!holdTime && bFollowingPath) ||
			user_turnspeed_angle_idle ||
			user_turnspeed_pitch_idle ||
			user_turnspeed_roll_idle ||
			bUserSoundsShouldMove ||
			(vel != (0, 0, 0) && vel.LengthSquared() > MISCUSERVAR_LOWVEL)
		);

		//'shouldMove' being false nullifies the rest because we don't
		//want random teleportation to trigger "start"/"move" sounds
		//unless the teleportation is caused by ACSFuncInterpolate()
		bool hasMoved = ( shouldMove && (
			pos != oldPos ||
			angle != oldAngle ||
			pitch != oldPitch ||
			roll != oldRoll ||
			bUserSoundsHasMoved )
		);

		return shouldMove, hasMoved;
	}

	//============================
	// HandleUserSounds
	//============================
	private void HandleUserSounds (bool shouldMove, bool hasMoved)
	{
		//Stop the looping "move" sound in case the next sound is invalid
		if ((!shouldMove || !bUserSoundsWasMoving) && IsActorPlayingSound(CHAN_USERSND, user_snd_move))
			A_StopSound(CHAN_USERSND);

		if (shouldMove && !bUserSoundsWasMoving && hasMoved)
		{
			A_StartSound(user_snd_start, CHAN_USERSND);
			startSoundTime = level.mapTime;
		}
		else if (!shouldMove && bUserSoundsWasMoving)
		{
			A_StartSound(user_snd_stop, CHAN_USERSND);
		}
		else if (shouldMove && bUserSoundsWasMoving)
		{
			if (hasMoved)
			{
				if ( ( user_snd_delaytomove > 0 && level.mapTime - startSoundTime > user_snd_delaytomove ) ||
					 ( user_snd_delaytomove <= 0 && !IsActorPlayingSound(CHAN_USERSND) ) )
				{
					int sndFlags = CHANF_LOOPING;
					if (!user_snd_movestopsstart)
						sndFlags |= CHANF_OVERLAP;
					A_StartSound(user_snd_move, CHAN_USERSND, sndFlags);
				}
			}
			else
			{
				A_StartSound(user_snd_blocked, CHAN_USERSND);
			}
		}

		bUserSoundsWasMoving = hasMoved;
		bUserSoundsShouldMove = false;
		bUserSoundsHasMoved = false;
	}

	//============================
	// HandlePathFollowing
	//============================
	private bool HandlePathFollowing ()
	{
		//This returns "false" if any actions taken here result in us getting destroyed
		//which can happen if we're affected by a Thing_Remove() call.

		if (holdTime > 0)
		{
			if (!--holdTime) //Finished waiting?
				MustGetNewPassengers(); //Ignore search tic rate; do a search now
			return true;
		}

		let [stillHere, success] = Interpolate();
		if (!stillHere)
			return false; //Abort if we got Thing_Remove()'d

		if (!success)
		{
			if (stuckActors.Size() || (portTwin && !portTwin.bNoBlockmap && portTwin.stuckActors.Size()))
				return true; //Don't bother

			//Something's blocking us so try to move a little closer
			if (reachedTime < time)
			{
				let oldTime = time;
				time = reachedTime + timeFrac * 0.125;
				[stillHere, success] = Interpolate();
				if (!stillHere)
					return false; //Abort if we got Thing_Remove()'d
				if (success)
					reachedTime = time;
				time = oldTime;
			}
			return true;
		}

		reachedTime = time;
		time += timeFrac;
		if (time > 1.0) //Reached destination?
		{
			//Take into account certain functions that can get called on self through CallNodeSpecials().
			bRanActivationRoutine = false; //SetInterpolationCoordinates() or Activate() was called.
			bRanACSSetupRoutine = false; //CommonACSSetup() was called.
			bTimeAlreadySet = false; //The 'time' variable has been changed.

			bool goneToNode = bGoToNode;
			if (bGoToNode)
			{
				bGoToNode = false; //Reached 'currNode'
			}
			else
			{
				prevNode = currNode;
				if (currNode)
					currNode = currNode.next;
			}

			if (currNode)
			{
				if (!CallNodeSpecials())
					return false; //Abort if we got Thing_Remove()'d

				if (prevNode && prevNode.bDestroyed)
				{
					prevNode = null; //Prev node got Thing_Remove()'d
				}
				if (currNode && currNode.bDestroyed)
				{
					currNode = null; //Current node got Thing_Remove()'d
				}
				else if (currNode &&
					currNode.next && currNode.next.bDestroyed)
				{
					currNode.next = null; //Next node got Thing_Remove()'d
				}
				else if (currNode && currNode.next &&
					currNode.next.next && currNode.next.next.bDestroyed)
				{
					currNode.next.next = null; //Last node got Thing_Remove()'d
				}
			}

			//ACS movement functions set 'time', 'timeFrac', 'holdTime' etc just like Activate() - so we might as well pretend Activate() was called
			bRanActivationRoutine |= bRanACSSetupRoutine;

			bool finishedPath = bRanACSSetupRoutine ? false : //The ACS side operates without interpolation nodes.
				((acsFlags & INTERNALFLAG_ACSMOVE) || //Finished ACS induced movement?
				!currNode || !currNode.next || //Reached our last node?
				(!goneToNode && !(options & OPTFLAG_LINEAR) && (!currNode.next.next || !prevNode) ) ); //Finished spline path?

			if (!bRanActivationRoutine && !finishedPath)
				SetHoldTime();

			if (finishedPath || holdTime > 0 || !bFollowingPath) //'bFollowingPath' being false can happen if CallNodeSpecials() ended up calling Deactivate() on self
			{
				//Stopped() must be called before PlatMove() in this case
				for (int i = -1; i == -1 || (group && i < group.members.Size()); ++i)
				{
					let plat = (i == -1) ? self : group.GetMember(i);
					if (i == -1 || (plat && plat != self)) //Already handled self
						plat.Stopped(plat.oldPos, plat.pos);
				}
			}

			if (reachedTime != 1.0 && (finishedPath || holdTime > 0) && (finishedPath || !bTimeAlreadySet) && !bRanActivationRoutine)
			{
				//Make sure we're exactly at our intended position.
				//(It doesn't matter if we can't fit at this "intended position"
				//because that's what the "stuck actors" logic is there for.)
				let oldTime = time;
				time = 1.0;
				Interpolate(MOVE_QUICK);
				time = oldTime;
			}

			if (finishedPath)
			{
				Deactivate(self);
			}
			else if (!bRanActivationRoutine)
			{
				let platNode = FishyPlatformNode(currNode.next);
				if (platNode && platNode.user_undopivotadjustment)
				{
					pNext += interpolatedPivotOffset;
					interpolatedPivotOffset = (0, 0, 0);
				}
				SetInterpolationCoordinates(pNext, pNextAngs);
				SetTimeFraction();
				if (!bTimeAlreadySet)
					time -= 1.0;

				//Don't go faster than the next point's travel time/speed would allow it.
				//This can happen if the previous speed was very high.
				if (time > timeFrac && !bTimeAlreadySet)
					time = timeFrac;

				reachedTime = time;
				vel = (0, 0, 0);
			}

			if (bTimeAlreadySet && !finishedPath && holdTime > 0)
				Interpolate(); //If we're pausing, try to be at whatever point 'time' is pointing to between two nodes
		}
		return (!bDestroyed);
	}

	//============================
	// Tick (override)
	//============================
	override void Tick ()
	{
		//Portal copies aren't meant to think themselves. Not even advance states.
		//The only thing a copy should do is remove itself if its twin is gone.
		if (bPortCopy)
		{
			if (!portTwin)
				Destroy();
			return;
		}

		if (freezeTics > 0)
		{
			--freezeTics;
			return;
		}

		if (IsFrozen())
			return;

		//Any of the copy's received velocities are passed on to the non-copy twin
		if (portTwin && portTwin.bPortCopy)
		{
			vector3 pVel = portTwin.vel;
			portTwin.vel = (0, 0, 0);

			if (lastUPort && pVel.xy != (0, 0))
				pVel = TranslatePortalVector(pVel, lastUPort, false, true);

			vel += pVel;
		}

		if (group)
		{
			if (group.members.Find(self) >= group.members.Size())
				group.members.Push(self); //Ensure we're in the group array

			if ((!group.origin || (!group.origin.bFollowingPath && group.origin.vel == (0, 0, 0))) && (bFollowingPath || vel != (0, 0, 0)))
			{
				SetGroupOrigin(self);
			}
			else if (group.origin && group.origin != self)
			{
				group.origin.vel += vel; //Any member's received velocity is passed on to the origin
				vel = (0, 0, 0);
				bFollowingPath = false; //Non-origin members aren't supposed to be "active"
			}

			//We need to check if the 'carrier' is actually carrying anyone in this group
			if (group.carrier && !(level.mapTime & 127) && //Do this roughly every 3.6 seconds
				group.GetMember(0) == self)
			{
				let carrier = group.carrier;
				int carrierPSize = carrier.passengers.Size();
				if (!carrierPSize)
				{
					group.carrier = null;
				}
				else for (int i = 0; i < group.members.Size();)
				{
					let plat = group.GetMember(i);
					if (plat && carrier.passengers.Find(plat) < carrierPSize)
						break; //It does carry one of us

					if (++i >= group.members.Size())
						group.carrier = null; //It doesn't carry any of us
				}
			}
		}

		double oldFloorZ = floorZ;

		// The group origin, if there is one, thinks for the whole group.
		// That means the order in which they think depends on where
		// they are in the group array and not where they are in the thinker list.
		// (In other words, the others think when the origin thinks/ticks.)
		//
		// The intent behind this is to keep the whole group in sync.
		// Especially when playing user var sounds as a group.
		// Like the moving bridge construct in map01.

		bool inactive;

		if (!group || !group.origin || group.origin == self)
		for (int i = -1; i == -1 || (group && group.origin == self && i < group.members.Size()); ++i)
		{
			let plat = (i == -1) ? self : group.GetMember(i);
			if (i > -1 && (!plat || plat == self)) //Already handled self
				continue;

			if (i == -1)
				inactive = (holdTime - 1 > 0 || !IsActive());

			for (int iTwins = 0; iTwins < 2; ++iTwins)
			{
				if (iTwins > 0 && !(plat = plat.portTwin))
					break;

				//Don't update the blockmap results while...
				if (plat.noBmapSearchTics > 0 && //The interval isn't over and...
					abs(plat.pos.x - plat.oldBmapSearchPos.x) < plat.radius && abs(plat.pos.y - plat.oldBmapSearchPos.y) < plat.radius ) //Not too far away from where the last blockmap search was done
				{
					--plat.noBmapSearchTics;
				}
				else
				{
					plat.GetNewBmapResults();
				}
				plat.bOnMobj = false; //Aside from standing on an actor, this can also be "true" later if hitting a lower obstacle while going down or we have stuck actors
				plat.HandleOldPassengers(inactive);
				plat.UpdateOldInfo();
				plat.bPlatPorted = false;
			}
		}

		// The group logic is incompatible with the native Tick() function.
		// For sanity's sake, I'm not going to bother to make it compatible.
		// Because being in a group affects gravity and friction.
		// And making that work with Actor.Tick() will give me a headache.
		// Besides that, movement in the world has to happen first before
		// any path following happens.
		// But calling Actor.Tick() will also change actor states.
		//
		// As it turns out, there's more to actor movement
		// besides checking velocity, handling gravity, friction.
		// Such as scrolling floors and bounce logic.
		// If you want bouncyness or scrolling or whatever else
		// is already handled natively then use Actor.Tick().
		//
		bool callActorTick = (!group && bUseActorTick);

		if (callActorTick)
		{
			vector3 startVel = vel;
			if (startVel != (0, 0, 0) && startVel.LengthSquared() <= MISCUSERVAR_LOWVEL)
				startVel = (0, 0, 0);

			if (lastGetBmapTime == level.mapTime)
				GetNewPassengers(false); //Call this early if we just did a blockmap search

			let oldPGroup = curSector.portalGroup;
			bInMove = true; //Don't collide with passengers
			Actor.Tick();
			if (bDestroyed)
				return; //Abort if we got Thing_Remove()'d
			bInMove = false;

			//If our position/angles have actually changed then go back and try to get here via PlatMove()
			if (pos != oldPos || angle != oldAngle || pitch != oldPitch || roll != oldRoll)
			{
				if (bFollowingPath && (pos != oldPos || angle != oldAngle))
				{
					if (bPlatPorted || curSector.portalGroup != oldPGroup)
						AdjustInterpolationCoordinates(oldPos, pos, DeltaAngle(oldAngle, angle));
					else
						pCurr += pos - oldPos; //Adjust for interpolation moves
				}
				let thisPos = pos;
				let thisAng = angle;
				let thisPi = pitch;
				let thisRo = roll;
				GoBack();
				PlatMove(thisPos, thisAng, thisPi, thisRo, MOVE_REPEAT);
			}
			else if (portTwin && portTwin.bNoBlockmap && portTwin.bPortCopy && !IsActive())
			{
				portTwin.Destroy(); //If we're not moving then remove our non-solid portal copy
			}

			if (!bOnMobj && pos.z > floorZ && vel != (0, 0, 0))
			{
				vel *= platAirFric;

				//For some reason Actor.Tick() doesn't take care of this(?)
				//so the 'minVel' check is necessary here, too
				//otherwise too much time is spent with a combined "zero velocity."
				if (abs(vel.x) < minVel) vel.x = 0;
				if (abs(vel.y) < minVel) vel.y = 0;
				if (abs(vel.z) < minVel) vel.z = 0;
			}

			if (vel == (0, 0, 0) && startVel != (0, 0, 0))
				bUserSoundsShouldMove = true; //Play "blocked" sound
		}
		else if (!group || group.origin == self)
		{
			if (!PlatVelMove())
				return; //Abort if we got Thing_Remove()'d
		}

		//Path following and idle turning (both influenced by pivot behavior)
		if (!group || !group.origin || group.origin == self)
		{
			if (bFollowingPath && !HandlePathFollowing())
				return; //We got destroyed

			if (!bInterpolateSuccess && //The last Interpolate() call (including from ACS) must not have moved us
				(user_turnspeed_angle_idle || user_turnspeed_pitch_idle || user_turnspeed_roll_idle ||
				user_turnspeed_angle_withvel || user_turnspeed_pitch_withvel || user_turnspeed_roll_withvel) &&
				!HandleNonPathTurnSpeeds() )
			{
				return; //We got destroyed
			}
		}
		bInterpolateSuccess = false;

		if (callActorTick)
		{
			let [shouldMove, hasMoved] = CheckUserSoundsMovement();
			HandleUserSounds(shouldMove, hasMoved);
			return;
		}

		//Handle friction, gravity, and other misc things
		if (!group || !group.origin || group.origin == self)
		{
			bool onGround = false;
			bool yesGravity = false;
			bool yesFriction = false;

			for (int i = -1; i == -1 || (group && group.origin == self && i < group.members.Size()); ++i)
			{
				let plat = (i == -1) ? self : group.GetMember(i);
				if (i > -1 && (!plat || plat == self)) //Already handled self
					continue;

				//If anyone in the group is gravity bound then everyone else is, too
				if (!plat.bNoGravity)
				{
					yesGravity = true;
					break;
				}
			}
			bool doStandOn = (!bFollowingPath && yesGravity);

			for (int i = -1; i == -1 || (group && group.origin == self && i < group.members.Size()); ++i)
			{
				let plat = (i == -1) ? self : group.GetMember(i);
				if (i > -1 && (!plat || plat == self)) //Already handled self
					continue;

				for (int iTwins = 0; iTwins < 2; ++iTwins)
				{
					if (iTwins > 0 && (!(plat = plat.portTwin) || plat.bNoBlockmap)) //NOBLOCKMAP means it's currently not in use
						break;

					plat.CheckFloorCeiling();
					plat.UpdateWaterLevel();

					if (group && group.origin)
						plat.bPushStuckActors |= group.origin.bPushStuckActors;

					if (plat.lastGetNPTime != level.mapTime) //Call it only if GetNewPassengers() wasn't called
						plat.GetStuckActors();
					plat.HandleStuckActors(doStandOn);

					if (!plat.bOnMobj && plat.pos.z > plat.floorZ)
					{
						Actor mo;
						plat.bOnMobj = (
							(plat.lastGetNPTime == level.mapTime && !plat.lastGetNPResult) ||
							((mo = plat.blockingMobj) && mo.pos.z <= plat.pos.z && OverlapXY(plat, mo)) ||
							!plat.TestMobjZ(true) );
					}

					//Find a member who is "on the ground" and/or doesn't ignore friction
					onGround |= (plat.bOnMobj || plat.pos.z <= plat.floorZ);
					yesFriction |= !plat.bNoFriction;
				}
			}

			if (yesFriction && vel != (0, 0, 0))
			{
				//Get the average friction from the group if there is a group
				int count = 0;
				double sum = 0;

				for (int i = -1; i == -1 || (group && group.origin == self && i < group.members.Size()); ++i)
				{
					let plat = (i == -1) ? self : group.GetMember(i);
					if (i > -1 && (!plat || plat == self)) //Already handled self
						continue;

					++count;
					if (!onGround)
					{
						sum += plat.platAirFric;
					}
					else
					{
						let oldNoGrav = plat.bNoGravity;
						plat.bNoGravity = false; //A little hack to make GetFriction() give us a actual friction value
						sum += plat.GetFriction();
						plat.bNoGravity = oldNoGrav;
					}
				}
				double fric = (count > 1) ? (sum / count) : sum;

				if (!onGround)
					vel *= fric;
				else
					vel.xy *= fric;

				if (abs(vel.x) < minVel) vel.x = 0;
				if (abs(vel.y) < minVel) vel.y = 0;
				if ((onGround && vel.z < 0) || abs(vel.z) < minVel) vel.z = 0;
			}

			if (yesGravity && !onGround)
			{
				//Get the average gravity from the group if there is a group
				int count = 0;
				double sum = 0;

				for (int i = -1; i == -1 || (group && group.origin == self && i < group.members.Size()); ++i)
				{
					let plat = (i == -1) ? self : group.GetMember(i);
					if (i > -1 && (!plat || plat == self)) //Already handled self
						continue;

					++count;
					let oldNoGrav = plat.bNoGravity;
					plat.bNoGravity = false;
					sum += plat.GetGravity();
					plat.bNoGravity = oldNoGrav;
				}
				double grav = (count > 1) ? (sum / count) : sum;

				FallAndSink(grav, oldFloorZ);
			}

			//If we're not moving (and with no velocity), find and destroy unused portal copies
			if (!IsActive())
			for (int i = -1; i == -1 || (group && group.origin == self && i < group.members.Size()); ++i)
			{
				let plat = (i == -1) ? self : group.GetMember(i);
				if (i > -1 && (!plat || plat == self)) //Already handled self
					continue;

				if (plat.portTwin && plat.portTwin.bNoBlockmap && plat.portTwin.bPortCopy)
					plat.portTwin.Destroy();
			}
		}

		//Handle user variable sounds and advance actor states
		if (!group || !group.origin || group.origin == self)
		{
			let [shouldMove, hasMoved] = CheckUserSoundsMovement();

			for (int i = -1; i == -1 || (group && group.origin == self && i < group.members.Size()); ++i)
			{
				let plat = (i == -1) ? self : group.GetMember(i);
				if (i > -1 && (!plat || plat == self)) //Already handled self
					continue;

				plat.HandleUserSounds(shouldMove, hasMoved);

				if (!plat.CheckNoDelay())
					continue; //Freed itself (ie got destroyed)

				if (plat.tics != -1 && --plat.tics <= 0)
					plat.SetState(plat.curState.nextState);
			}
		}
	}

	//============================
	// CheckFloorCeiling
	//============================
	private void CheckFloorCeiling ()
	{
		if (options & OPTFLAG_IGNOREGEO)
			return;

		if (IsActive() && !HasMoved(true)) //Possibly blocked?
			FindFloorCeiling(); //If there's a 3D floor, sets 'floorZ' and 'ceilingZ' accordingly.

		let oldZ = pos.z;

		if (pos.z < floorZ || ceilingZ - floorZ < height)
			SetZ(floorZ);
		else if (pos.z + height > ceilingZ)
			SetZ(ceilingZ - height);

		pCurr.z += pos.z - oldZ;
	}

	//============================
	// FallAndSink (override)
	//============================
	override void FallAndSink (double grav, double oldFloorZ)
	{
		//This is a modified version of the original function
		if (!grav)
			return;

		double startVelZ = vel.z;

		//Get the average water level and average mass from the group if there is a group
		int count = 0;
		int sums[2] = {0, 0};

		for (int i = -1; i == -1 || (group && group.origin == self && i < group.members.Size()); ++i)
		{
			let plat = (i == -1) ? self : group.GetMember(i);
			if (i > -1 && (!plat || plat == self)) //Already handled self
				continue;

			++count;
			sums[0] += plat.waterLevel;
			sums[1] += plat.mass;
		}
		int wLevel = (count > 1) ? (sums[0] / count) : sums[0];
		int m = (count > 1) ? (sums[1] / count) : sums[1];

		if (wLevel == 0)
		{
			// [RH] Double gravity only if running off a ledge. Coming down from
			// an upward thrust (e.g. a jump) should not double it.
			if (vel.z == 0 && oldFloorZ > floorZ && pos.z == oldFloorZ)
				vel.z -= grav + grav;
			else
				vel.z -= grav;
		}
		else if (wLevel >= 1)
		{
			double sinkSpeed = -0.5; // -WATER_SINK_SPEED;

			// Scale sinkSpeed by mass (m), with
			// 100 being equivalent to a player.
			sinkSpeed = sinkSpeed * clamp(m, 1, 4000) / 100;

			if (vel.z < sinkSpeed)
			{ // Dropping too fast, so slow down toward sinkSpeed.
				vel.z -= max(sinkSpeed * 2, -8.0);
				if (vel.z > sinkSpeed)
					vel.z = sinkSpeed;
			}
			else if (vel.z > sinkSpeed)
			{ // Dropping too slow/going up, so trend toward sinkSpeed.
				vel.z = startVelZ + max(sinkSpeed / 3, -8.0);
				if (vel.z < sinkSpeed)
					vel.z = sinkSpeed;
			}
		}
	}

	//============================
	// IsActive
	//============================
	bool IsActive ()
	{
		//Portal copies should check their twin
		let plat = bPortCopy ? portTwin : self;

		//When checking group members we only care about the origin.
		//Either "every member is active" or "every member is not active."
		if (plat.group && plat.group.origin)
			plat = plat.group.origin;

		return (plat.bFollowingPath ||
			plat.vel != (0, 0, 0) ||
			plat.user_turnspeed_angle_idle ||
			plat.user_turnspeed_pitch_idle ||
			plat.user_turnspeed_roll_idle);
	}

	//============================
	// HasMoved
	//============================
	bool HasMoved (bool posOnly = false)
	{
		//Portal copies should check their twin
		let plat = bPortCopy ? portTwin : self;

		//When checking group members we only care about the origin.
		//Either "every member has moved" or "every member has not moved."
		if (plat.group && plat.group.origin)
			plat = plat.group.origin;

		bool activity = (plat.bFollowingPath ||
			plat.vel != (0, 0, 0) ||
			plat.user_turnspeed_angle_idle ||
			plat.user_turnspeed_pitch_idle ||
			plat.user_turnspeed_roll_idle);

		return (activity && (plat.pos != plat.oldPos ||
				(!posOnly && plat.angle != plat.oldAngle) ||
				(!posOnly && plat.pitch != plat.oldPitch) ||
				(!posOnly && plat.roll != plat.oldRoll) ) );
	}

	//============================
	// FirstCommonACSSetup
	//============================
	private void FirstCommonACSSetup ()
	{
		time = 0;
		reachedTime = 0;
		holdTime = 0;
		bTimeAlreadySet = true;
		bFollowingPath = true;
		if (group && group.origin != self)
			SetGroupOrigin(self, setNonOriginNoFollow: true);
		portDelta = 0;
		acsFlags = (INTERNALFLAG_ACSMOVE | OPTFLAG_ANGLE | OPTFLAG_PITCH | OPTFLAG_ROLL);
		pPrev = pos;
		pCurr = pos;
		pCurrAngs = (
			Normalize180(angle),
			Normalize180(pitch),
			Normalize180(roll));
		pPrevAngs = pCurrAngs;
		interpolatedPivotOffset = (0, 0, 0);
		vel = (0, 0, 0);
		MustGetNewPassengers(); //Ignore search tic rate; do a search now
		bRanACSSetupRoutine = true;
	}

	//============================
	// LastCommonACSSetup
	//============================
	private void LastCommonACSSetup (int travelTime)
	{
		//Make "onpath" turnspeeds work if there's no ACS given rotation
		if (pNextAngs.x == pCurrAngs.x && user_turnspeed_angle_onpath)
			acsFlags &= ~OPTFLAG_ANGLE;
		if (pNextAngs.y == pCurrAngs.y && user_turnspeed_pitch_onpath)
			acsFlags &= ~OPTFLAG_PITCH;
		if (pNextAngs.z == pCurrAngs.z && user_turnspeed_roll_onpath)
			acsFlags &= ~OPTFLAG_ROLL;

		if (travelTime <= 0) //Negative values are interpreted as speed in map units per tic
			SetTravelSpeed(-travelTime);
		else
			timeFrac = 1.0 / travelTime; //Time unit is always in tics from the ACS side
	}

	//
	//
	// Everything below this point are
	// ACS centric utility functions.
	//
	//

	//============================
	// ACSFuncMove
	//============================
	static void ACSFuncMove (Actor act, int platTid, double x, double y, double z, bool exactPos, int travelTime, double ang = 0, double pi = 0, double ro = 0, bool exactAngs = false)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FishyPlatform") : null;
		for (let plat = FishyPlatform(it ? it.Next() : act); plat; plat = it ? FishyPlatform(it.Next()) : null)
		{
			plat.FirstCommonACSSetup();

			plat.pNext = plat.pos + (exactPos ?
				level.Vec3Diff(plat.pos, (x, y, z)) : //Make it portal aware in a way so TryMove() can handle it
				(x, y, z)); //Absolute offset so TryMove() can handle it
			plat.pLast = plat.pNext;

			plat.pNextAngs = plat.pCurrAngs + (
				exactAngs ? DeltaAngle(plat.pCurrAngs.x, ang) : ang,
				exactAngs ? DeltaAngle(plat.pCurrAngs.y, pi) : pi,
				exactAngs ? DeltaAngle(plat.pCurrAngs.z, ro) : ro);
			plat.pLastAngs = plat.pNextAngs;

			plat.LastCommonACSSetup(travelTime);
		}
	}

	//============================
	// ACSFuncMoveToSpot
	//============================
	static void ACSFuncMoveToSpot (Actor act, int platTid, int spotTid, int travelTime, bool dontRotate = false)
	{
		//This is the only place you can make a platform use any actor as a travel destination
		ActorIterator it = spotTid ? level.CreateActorIterator(spotTid) : null;
		Actor spot = it ? it.Next() : act;
		if (!spot)
			return; //No spot? Nothing to do

		it = platTid ? level.CreateActorIterator(platTid, "FishyPlatform") : null;
		for (let plat = FishyPlatform(it ? it.Next() : act); plat; plat = it ? FishyPlatform(it.Next()) : null)
		{
			plat.FirstCommonACSSetup();

			plat.pNext = plat.pos + plat.Vec3To(spot); //Make it portal aware in a way so TryMove() can handle it
			plat.pLast = plat.pNext;

			plat.pNextAngs = plat.pCurrAngs + (
				!dontRotate ? DeltaAngle(plat.pCurrAngs.x, spot.angle) : 0,
				!dontRotate ? DeltaAngle(plat.pCurrAngs.y, spot.pitch) : 0,
				!dontRotate ? DeltaAngle(plat.pCurrAngs.z, spot.roll) : 0);
			plat.pLastAngs = plat.pNextAngs;

			plat.LastCommonACSSetup(travelTime);
		}
	}

	//============================
	// ACSFuncIsActive
	//============================
	static bool ACSFuncIsActive (Actor act, int platTid)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FishyPlatform") : null;
		for (let plat = FishyPlatform(it ? it.Next() : act); plat; plat = it ? FishyPlatform(it.Next()) : null)
		{
			if (plat.IsActive())
				return true;
		}
		return false;
	}

	//============================
	// ACSFuncHasMoved
	//============================
	static bool ACSFuncHasMoved (Actor act, int platTid, bool posOnly = false)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FishyPlatform") : null;
		for (let plat = FishyPlatform(it ? it.Next() : act); plat; plat = it ? FishyPlatform(it.Next()) : null)
		{
			if (plat.HasMoved(posOnly))
				return true;
		}
		return false;
	}

	//============================
	// ACSFuncSetNodePath
	//============================
	static void ACSFuncSetNodePath (Actor act, int platTid, int nodeTid)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FishyPlatform") : null;
		for (let plat = FishyPlatform(it ? it.Next() : act); plat; plat = it ? FishyPlatform(it.Next()) : null)
		{
			if (plat.SetUpPath(nodeTid, false) && !plat.bFollowingPath)
				plat.pCurr.x = double.nan; //Tell ACSFuncInterpolate() to call SetInterpolationCoordinates()
		}
	}

	//============================
	// ACSFuncSetOptions
	//============================
	static void ACSFuncSetOptions (Actor act, int platTid, int toSet, int toClear = 0)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FishyPlatform") : null;
		for (let plat = FishyPlatform(it ? it.Next() : act); plat; plat = it ? FishyPlatform(it.Next()) : null)
		{
			// NOTE: Changing most options on an active platform has an immediate effect except for
			// 'OPTFLAG_GOTONODE' which is checked in Activate() meaning you can't stop it from
			// going to the first node once it's started. (Not like this anyway).
			//
			// And changing 'OPTFLAG_STARTACTIVE' after it has called PostBeginPlay() is utterly pointless.

			//-1 means the platform hasn't called PostBeginPlay() yet
			int oldFlags = (plat.options != -1) ? plat.options : 0;
			int newFlags = (oldFlags & ~toClear) | toSet;
			plat.options = newFlags;

			//If for some reason you wanted to cancel ACS induced rotations, you can do it this way
			plat.acsFlags &= ~(toClear & (OPTFLAG_ANGLE | OPTFLAG_PITCH | OPTFLAG_ROLL));

			//If the "mirror" option has changed and the group has an "origin", we must
			//update the group info. (Having an "origin" usually means they are moving.)
			if (((oldFlags ^ newFlags) & OPTFLAG_MIRROR) && plat.group && plat.group.origin && plat != plat.group.origin)
				plat.UpdateGroupInfo();

			//If the mapper wants realtime passenger fetching right now
			//then the search tics need to be discarded for this to take effect.
			if (newFlags & OPTFLAG_REALTIMEBMAP)
				plat.noBmapSearchTics = 0;
		}
	}

	//============================
	// ACSFuncGetOptions
	//============================
	static int ACSFuncGetOptions (Actor act, int platTid)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FishyPlatform") : null;
		let plat = FishyPlatform(it ? it.Next() : act);
		return plat ? plat.options : 0;
	}

	//============================
	// ACSFuncSetCrushDamage
	//============================
	static void ACSFuncSetCrushDamage (Actor act, int platTid, int damage)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FishyPlatform") : null;
		for (let plat = FishyPlatform(it ? it.Next() : act); plat; plat = it ? FishyPlatform(it.Next()) : null)
			plat.crushDamage = damage;
	}

	//============================
	// ACSFuncGetCrushDamage
	//============================
	static int ACSFuncGetCrushDamage (Actor act, int platTid)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FishyPlatform") : null;
		let plat = FishyPlatform(it ? it.Next() : act);
		return plat ? plat.crushDamage : 0;
	}

	//============================
	// ACSFuncMakeGroup
	//============================
	static void ACSFuncMakeGroup (Actor act, int platTid, int otherPlatTid)
	{
		if (platTid && !otherPlatTid)
		{
			//Swap them. (If zero, 'otherPlatTid' is activator.)
			otherPlatTid = platTid;
			platTid = 0;
		}

		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FishyPlatform") : null;
		for (let plat = FishyPlatform(it ? it.Next() : act); plat; plat = it ? FishyPlatform(it.Next()) : null)
			plat.SetUpGroup(otherPlatTid, true);
	}

	//============================
	// ACSFuncLeaveGroup
	//============================
	static void ACSFuncLeaveGroup (Actor act, int platTid)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FishyPlatform") : null;
		for (let plat = FishyPlatform(it ? it.Next() : act); plat; plat = it ? FishyPlatform(it.Next()) : null)
		{
			if (!plat.group)
				continue;

			int index = plat.group.members.Find(plat);
			if (index < plat.group.members.Size())
				plat.group.members.Delete(index);

			if (plat.group.origin == plat)
				plat.group.origin = null;

			plat.group = null;
		}
	}

	//============================
	// ACSFuncDisbandGroup
	//============================
	static void ACSFuncDisbandGroup (Actor act, int platTid)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FishyPlatform") : null;
		for (let plat = FishyPlatform(it ? it.Next() : act); plat; plat = it ? FishyPlatform(it.Next()) : null)
		{
			if (!plat.group)
				continue;

			for (int i = 0; i < plat.group.members.Size(); ++i)
			{
				let member = plat.group.GetMember(i);
				if (member && member != plat)
					member.group = null;
			}
			plat.group = null;
		}
	}

	//============================
	// ACSFuncSetAirFriction
	//============================
	static void ACSFuncSetAirFriction (Actor act, int platTid, double fric)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FishyPlatform") : null;
		for (let plat = FishyPlatform(it ? it.Next() : act); plat; plat = it ? FishyPlatform(it.Next()) : null)
			plat.platAirFric = fric;
	}

	//============================
	// ACSFuncGetAirFriction
	//============================
	static double ACSFuncGetAirFriction (Actor act, int platTid)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FishyPlatform") : null;
		let plat = FishyPlatform(it ? it.Next() : act);
		return plat ? plat.platAirFric : 0;
	}

	//============================
	// ACSFuncHasPassenger
	//============================
	static bool ACSFuncHasPassenger (Actor act, int platTid, int passTid)
	{
		if ((!platTid && !passTid) || //No point if both are zero.
			(!act && (!platTid || !passTid)) ) //If there's no activator then we can't do anything if one of the TIDs is zero.
		{
			return false;
		}

		//Iterate only once when looking for anything with 'passTid'
		//in case there are multiple platforms with 'platTid'
		//that we have to go through.
		//(In other words, avoid creating multiple iterators for 'passTid'.)
		Array<Actor> passList;
		if (!passTid)
		{
			passList.Push(act);
		}
		else
		{
			let it = level.CreateActorIterator(passTid);
			Actor mo;
			while (mo = it.Next())
				passList.Push(mo);
		}

		if (!passList.Size())
			return false; //Nothing to look for; don't create an iterator for 'platTid'

		//Now we go through the platforms and see if any of them has someone in 'passList'
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FishyPlatform") : null;
		for (let plat = FishyPlatform(it ? it.Next() : act); plat; plat = it ? FishyPlatform(it.Next()) : null)
		{
			//If there's a portal twin (copy), we're going to check its passengers, too
			for (int iTwins = 0; iTwins < 2; ++iTwins)
			{
				if (iTwins > 0 && !(plat = plat.portTwin))
					break;

				plat.GetNewBmapResults();
				plat.GetNewPassengers(false); //Take into account idle platforms because those don't look for passengers
				int pSize = plat.passengers.Size();
				if (!pSize)
					continue; //This platform has no passengers

				for (uint i = passList.Size(); i-- > 0;)
				{
					if (plat.passengers.Find(passList[i]) < pSize)
						return true;
				}
			}
		}
		return false;
	}

	//============================
	// ACSFuncInterpolate
	//============================
	static int ACSFuncInterpolate (Actor act, int platTid, double newTime, bool teleMove)
	{
		newTime = clamp(newTime, 0.0, 1.0); //Because this only makes sense if the range is between 0.0 and 1.0
		int count = 0;
		Array<FishyPlatform> platList;

		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FishyPlatform") : null;
		for (let plat = FishyPlatform(it ? it.Next() : act); plat; plat = it ? FishyPlatform(it.Next()) : null)
		{
			if (plat.pCurr != plat.pCurr) //NaN check
			{
				plat.bGoToNode = (plat.options & OPTFLAG_GOTONODE);
				plat.currNode = plat.firstNode;
				plat.prevNode = plat.firstPrevNode;
				if (!plat.currNode || (!plat.currNode.next && !plat.bGoToNode))
					continue; //Not enough nodes

				plat.portDelta = 0;
				plat.acsFlags = 0;

				vector3 startPos = plat.pos;
				if (!plat.bGoToNode)
				{
					let platNode = FishyPlatformNode(plat.currNode);
					startPos = !platNode ? plat.currNode.pos :
						platNode.FilterNoPosChange(noChange: plat.pos, yesChange: plat.currNode.pos);
				}
				vector3 startAngs = (plat.bGoToNode ? plat.angle : plat.currNode.angle,
					plat.bGoToNode ? plat.pitch : plat.currNode.pitch,
					plat.bGoToNode ? plat.roll : plat.currNode.roll);
				plat.SetInterpolationCoordinates(startPos, startAngs);
				plat.interpolatedPivotOffset = (0, 0, 0);
				plat.SetTimeFraction();
				plat.SetHoldTime();
				plat.bRanActivationRoutine = true;
			}

			//If the platform has the right actor flags, Interpolate() can
			//end up activating a line that removes/destroys the platform which
			//in turn messes up the iterator. Therefore do not call Interpolate()
			//while we're iterating right now.
			platList.Push(plat);
		}

		for (uint i = platList.Size(); i-- > 0;)
		{
			let oldTime = platList[i].time;
			platList[i].time = newTime;
			platList[i].bUserSoundsShouldMove = true;

			let [stillHere, success] = platList[i].Interpolate(teleMove ? MOVE_TELEPORT : MOVE_NORMAL);
			if (success)
				++count;
			if (!stillHere)
				continue; //This platform got destroyed

			if (success)
			{
				platList[i].reachedTime = newTime;
				platList[i].bTimeAlreadySet = true;
				platList[i].bUserSoundsHasMoved = true;
			}
			else
			{
				platList[i].time = oldTime;
			}
		}
		return count;
	}

	//============================
	// ACSFuncNextNode
	//============================
	static int ACSFuncNextNode (Actor act, int platTid)
	{
		int count = 0;

		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FishyPlatform") : null;
		for (let plat = FishyPlatform(it ? it.Next() : act); plat; plat = it ? FishyPlatform(it.Next()) : null)
		{
			if (!plat.currNode)
				continue; //No current? Then there can't be a next one

			if (plat.bGoToNode)
			{
				plat.bGoToNode = false;
			}
			else
			{
				if (!plat.currNode.next ||
					!plat.currNode.next.next ||
					(!plat.currNode.next.next.next && !(plat.options & OPTFLAG_LINEAR) ) )
				{
					continue;
				}
				plat.prevNode = plat.currNode;
				plat.currNode = plat.currNode.next;
			}

			//In case the platform is active and/or uses OPTFLAG_RESUMEPATH
			let platNode = FishyPlatformNode(plat.currNode);
			vector3 startPos = !platNode ? plat.currNode.pos :
				platNode.FilterNoPosChange(noChange: plat.pos, yesChange: plat.currNode.pos);
			plat.SetInterpolationCoordinates(startPos, (plat.currNode.angle, plat.currNode.pitch, plat.currNode.roll));
			plat.SetTimeFraction();
			plat.SetHoldTime();
			plat.time = 0;
			plat.reachedTime = 0;
			plat.bTimeAlreadySet = true;
			plat.bRanActivationRoutine = true;
			++count;
		}
		return count;
	}

	//============================
	// ACSFuncPrevNode
	//============================
	static int ACSFuncPrevNode (Actor act, int platTid)
	{
		int count = 0;

		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FishyPlatform") : null;
		for (let plat = FishyPlatform(it ? it.Next() : act); plat; plat = it ? FishyPlatform(it.Next()) : null)
		{
			if (!plat.prevNode || plat.bGoToNode)
				continue;

			InterpolationPoint nextPrevNode = null;
			for (let node = plat.firstPrevNode ? plat.firstPrevNode : plat.firstNode; node; node = node.next)
			{
				if (node.next == plat.prevNode)
				{
					nextPrevNode = node;
					break;
				}
			}

			if (!nextPrevNode && !(plat.options & OPTFLAG_LINEAR))
				continue;
			plat.currNode = plat.prevNode;
			plat.prevNode = nextPrevNode;

			//In case the platform is active and/or uses OPTFLAG_RESUMEPATH
			let platNode = FishyPlatformNode(plat.currNode);
			vector3 startPos = !platNode ? plat.currNode.pos :
				platNode.FilterNoPosChange(noChange: plat.pos, yesChange: plat.currNode.pos);
			plat.SetInterpolationCoordinates(startPos, (plat.currNode.angle, plat.currNode.pitch, plat.currNode.roll));
			plat.SetTimeFraction();
			plat.SetHoldTime();
			plat.time = 0;
			plat.reachedTime = 0;
			plat.bTimeAlreadySet = true;
			plat.bRanActivationRoutine = true;
			++count;
		}
		return count;
	}

	//============================
	// ACSFuncSetPivot
	//============================
	static void ACSFuncSetPivot (Actor act, int platTid, double x, double y, double z, bool exactPos, bool attach)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FishyPlatform") : null;
		for (let plat = FishyPlatform(it ? it.Next() : act); plat; plat = it ? FishyPlatform(it.Next()) : null)
		{
			vector3 pivot = exactPos ? (x, y, z) : level.Vec3Offset(plat.pos, (x, y, z));
			plat.SetPivot(pivot, attach);
		}
	}

	//============================
	// ACSFuncRemovePivot
	//============================
	static void ACSFuncRemovePivot (Actor act, int platTid)
	{
		ActorIterator it = platTid ? level.CreateActorIterator(platTid, "FishyPlatform") : null;
		for (let plat = FishyPlatform(it ? it.Next() : act); plat; plat = it ? FishyPlatform(it.Next()) : null)
		{
			plat.bPivotVectorIsPosition = false;
			plat.pivotVector = (0, 0, 0);
		}
	}
} //End of FishyPlatform class definition

/******************************************************************************

 The following concerns old classes that make use of the old
 InterpolationPoint class. They should not use FishyPlatformNode
 since it wasn't made for them.

******************************************************************************/

struct FishyOldStuff_Common play
{
	static void CheckNodeTypes (Actor pointer)
	{
		InterpolationPoint node;
		Array<InterpolationPoint> foundNodes; //To avoid infinite loops

		if (pointer is "PathFollower")
			node = InterpolationPoint(pointer.lastEnemy ? pointer.lastEnemy : pointer.target);
		else
			node = InterpolationPoint(pointer).next;

		//Go through the detected nodes. If any of them are the new type
		//then bluntly and forcefully inform the mapper that's a no-no.
		while (node)
		{
			if (foundNodes.Find(node) < foundNodes.Size())
				return;
			foundNodes.Push(node);

			if (node is "FishyPlatformNode")
			{
				String cls = pointer.GetClassName();
				cls.Replace("FishyOldStuff_", "");
				Console.Printf("\ck'" .. cls .. "' with tid " .. pointer.tid .. " at position " .. pointer.pos ..
							":\nis pointing at a 'Platform Interpolation Point' with tid ".. node.tid .. " at position " .. node.pos .. "\n.");
				FishyDelayedAbort.Create(Object.TICRATE, FishyDelayedAbort.INTERPOLATIONPOINT_ERROR);
			}

			pointer = node;
			node = node.next;
		}
	}
}

mixin class FishyOldStuff
{
	override void PostBeginPlay ()
	{
		Super.PostBeginPlay();
		FishyOldStuff_Common.CheckNodeTypes(self);
	}
}

class FishyOldStuff_PathFollower : PathFollower replaces PathFollower { mixin FishyOldStuff; }
class FishyOldStuff_MovingCamera : MovingCamera replaces MovingCamera { mixin FishyOldStuff; }
class FishyOldStuff_ActorMover : ActorMover replaces ActorMover { mixin FishyOldStuff; }

class FishyPlatformGeneric : FishyPlatform
{
	Default
	{
		//$Title Generic Platform (set model and size in the 'Custom' tab. Setting scale also affects size.)
		Radius 16; //A visual size for UDB's Visual Mode since it has a default model
		Height 16;
	}

	States
	{
	Spawn:
		MODL A -1; //In order to use A_ChangeModel() it needs to have a MODELDEF entry with a sprite other than TNT1A0
		Stop;
	}

	//===User variables that are parameters for A_SetSize() and A_ChangeModel()===//
	//$UserDefaultValue -1
	double user_set_radius;
	//$UserDefaultValue -1
	double user_set_height;

	//$UserDefaultValue true
	bool user_modelsetssize;

	string user_cm_modeldef;
	int user_cm_modelindex;
	string user_cm_modelpath;
	string user_cm_model;
	int user_cm_skinindex;
	string user_cm_skinpath;
	string user_cm_skin;
	int user_cm_flags;
	//$UserDefaultValue -1
	int user_cm_generatorindex;
	int user_cm_animationindex;
	string user_cm_animationpath;
	string user_cm_animation;

	override void BeginPlay () //This gets called before any user vars are set - any atypical default values have to be set here
	{
		Super.BeginPlay();
		user_set_radius = -1; //Passing a negative value to A_SetSize() means "don't change"
		user_set_height = -1;
		user_cm_generatorindex = -1;
		//Will not set 'user_modelsetssize' to "true" here
	}

	override void PostBeginPlay ()
	{
		if (!IsPortalCopy())
		{
			A_ChangeModel(
				user_cm_modeldef,
				user_cm_modelindex,
				user_cm_modelpath,
				user_cm_model,
				user_cm_skinindex,
				user_cm_skinpath,
				user_cm_skin,
				user_cm_flags,
				user_cm_generatorindex,
				user_cm_animationindex,
				user_cm_animationpath,
				user_cm_animation
			);

			if (!user_modelsetssize || !SetSizeFromModel())
				A_SetSize(user_set_radius, user_set_height);
		}
		Super.PostBeginPlay();
	}

	// Notes about the ScriptScanner:
	// bool GetString() advances the parser.
	// string GetStringContents() does NOT advance the parser.
	// void MustGetFloat() advances the parser.
	// void MustGetNumber() advances the parser.

	private string GetNextString (out ScriptScanner sc)
	{
		return sc.GetString() ? sc.GetStringContents() : ""; //Just to make things a tad more readable
	}

	private bool SetSizeFromModel ()
	{
		int lump = -1;
		ScriptScanner sc = null;
		string path = user_cm_modelpath;
		string model = user_cm_model;

		if (path != "" && model != "" && path.Mid(path.Length() - 1, 1) != "/")
			path = path .. "/"; //Make sure the last character of 'path' is "/"
		string fullName = path .. model;

		if (fullName == "" && user_cm_modeldef != "")
		{
			//Attempt to fetch model from MODELDEF.
			//If the matching MODELDEF entry contains multiple models
			//then the last defined model is going to be used.
			while ((lump = Wads.FindLump("MODELDEF", lump + 1)) >= 0) //Go through every MODELDEF lump/file
			{
				if (!sc)
					sc = new("ScriptScanner");
				sc.OpenLumpNum(lump);
				sc.SetPrependMessage("Expected numeric value, but\n"); //Part of error message if MustGetNumber() doesn't get a number
				while (!sc.end)
				{
					if (GetNextString(sc) ~== "model" &&
						GetNextString(sc) ~== user_cm_modeldef &&
						GetNextString(sc) == "{")
					{
						string str;
						while (!sc.end && (str = GetNextString(sc)) != "}")
						{
							if (str ~== "path")
							{
								path = GetNextString(sc);
							}
							else if (str ~== "model")
							{
								sc.MustGetNumber(); //Get this out of the way
								model = GetNextString(sc);
							}
						}
					}
				}
			}

			if (path != "" && model != "" && path.Mid(path.Length() - 1, 1) != "/")
				path = path .. "/"; //Make sure the last character of 'path' is "/"
			fullName = path .. model;
		}

		if (fullName != "")
		{
			int len = fullName.Length();
			if (len <= 4 || !(fullName.Mid(len - 4, 4) ~== ".obj"))
			{
				Console.Printf("\ckSetSizeFromModel(): invalid model: '"..fullName.."' only .obj files can be parsed."..
					"\n\ckPlatform position: "..pos.." tid: "..tid.."\n.");
				new("FishyModelDelayedAbort");
				return false;
			}

			lump = Wads.FindLumpFullName(fullName);
			if (lump < 0)
			{
				Console.Printf("\ckSetSizeFromModel(): invalid model: '"..fullName.."' can't be found."..
					"\n\ckPlatform position: "..pos.." tid: "..tid.."\n.");
				new("FishyModelDelayedAbort");
				return false;
			}
		}

		if (lump >= 0)
		{
			double newRad = 0;
			double newHi = 0;

			if (!sc)
				sc = new("ScriptScanner");
			sc.OpenLumpNum(lump);
			sc.SetPrependMessage("Expected float value, but\n"); //Part of error message if MustGetFloat() doesn't get a number
			while (!sc.end)
			{
				if (GetNextString(sc) ~== "v")
				{
					sc.MustGetFloat(); double x = sc.float;
					sc.MustGetFloat(); double z = sc.float;
					sc.MustGetFloat(); double y = sc.float;

					newRad = max(newRad, abs(x), abs(y));
					newHi = max(newHi, z);
				}
			}

			//I don't know how UDB does the conversion but the highest Z vertex
			//is always higher than the resulting height for an actor when exporting OBJ models.
			newHi *= 0.83333; //This should give the appropriate height in most cases.
			A_SetSize(newRad, newHi);
			return true;
		}
		return false;
	}
}

class FishyModelDelayedAbort : Thinker
{
	int startTime;

	override void PostBeginPlay ()
	{
		startTime = level.mapTime;
	}

	override void Tick ()
	{
		if (level.mapTime - startTime > 2)
			ThrowAbortException("SetSizeFromModel() errors.");
	}
}

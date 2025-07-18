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
		MODL A -1; //In order to use A_ChangeModel() it needs to have a modeldef entry with a sprite other than TNT1A0
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

	private bool NextStringIs (string compare, out ScriptScanner scanner)
	{
		return (scanner.GetString() && scanner.GetStringContents() ~== compare); //Just to make things a tad more readable
	}

	private bool SetSizeFromModel ()
	{
		int lump = -1;
		ScriptScanner scanner = null;
		string path = user_cm_modelpath;
		string model = user_cm_model;

		//Make sure the last character of 'path' is /
		if (path != "" && model != "" && path.Mid(path.Length() - 1, 1) != "/")
			path = path .. "/";

		string fullName = path .. model;

		if (fullName == "")
		{
			//Attempt to fetch model from MODELDEF.
			//If the matching MODELDEF entry contains multiple models
			//then the last defined model is going to be used.
			while ((lump = Wads.FindLump("MODELDEF", lump + 1)) >= 0) //Go through every MODELDEF lump/file
			{
				if (!scanner)
					scanner = new("ScriptScanner");
				scanner.OpenLumpNum(lump);
				scanner.SetPrependMessage("Expected numeric value, but\n"); //Part of error message if MustGetNumber() doesn't get a number
				while (!scanner.end)
				{
					if (NextStringIs("model", scanner) &&
						NextStringIs(user_cm_modeldef, scanner) &&
						NextStringIs("{", scanner))
					{
						while (!scanner.end && !NextStringIs("}", scanner))
						{
							string contents = scanner.GetStringContents();
							if (contents ~== "path")
							{
								scanner.GetString(); path = scanner.GetStringContents();
							}
							else if (contents ~== "model")
							{
								scanner.MustGetNumber(); //Get this out of the way
								scanner.GetString(); model = scanner.GetStringContents();
							}
						}
					}
				}
				
			}

			//Make sure the last character of 'path' is /
			if (path != "" && model != "" && path.Mid(path.Length() - 1, 1) != "/")
				path = path .. "/";

			fullName = path .. model;
		}

		if (fullName != "")
		{
			if (!(fullName.Mid(fullName.Length() - 4, 4) ~== ".obj"))
				ThrowAbortException("SetSizeFromModel(): only .obj files can be parsed at the moment. Sorry!");

			lump = Wads.FindLumpFullName(fullName);
			if (lump < 0)
				ThrowAbortException("SetSizeFromModel(): invalid model: "..fullName);
		}

		if (lump >= 0)
		{
			double newRad = radius;
			double newHi = height;

			if (!scanner)
				scanner = new("ScriptScanner");
			scanner.OpenLumpNum(lump);
			scanner.SetPrependMessage("Expected float value, but\n"); //Part of error message if MustGetFloat() doesn't get a number
			while (!scanner.end)
			{
				if (NextStringIs("v", scanner))
				{
					scanner.MustGetFloat(); double x = scanner.float;
					scanner.MustGetFloat(); double z = scanner.float;
					scanner.MustGetFloat(); double y = scanner.float;

					newRad = max(newRad, abs(x), abs(y));
					newHi = max(newHi, z * 0.85); //The highest Z is too tall for what it visually looks like. Need to figure out better conversion method.
				}
			}
			if (radius != newRad || height != newHi)
			{
				A_SetSize(newRad, newHi);
				return true;
			}
		}
		return false;
	}
}

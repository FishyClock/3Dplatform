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

	//===User variables that are parameters for A_SetSize()===//
	//Reference: https://zdoom.org/wiki/A_SetSize
	//$UserDefaultValue -1
	double user_set_radius;
	//$UserDefaultValue -1
	double user_set_height;

	//$UserDefaultValue true
	bool user_modelsetssize; //If true and a model is provided, this will override user_set_height and user_set_radius

	//===User variables that are parameters for A_ChangeModel()===//
	//Reference: https://zdoom.org/wiki/A_ChangeModel

	//The flag (bit) values for 'user_cm_flags':
	//https://github.com/UZDoom/UZDoom/blob/c34025d88b8cfa19c6140a00cd0c8919ce7cd4d7/wadsrc/static/zscript/constants.zs#L404-L410

	// While you can use this however you want, the usual intended practice is
	// set 'user_cm_modelpath' to the path (if any) where your models are
	// and set 'user_cm_model' to the model file, including its extension.
	//
	// Alternatively you can just set 'user_cm_model' to "modelpath/modelfile.extension"
	// and it will work.
	string user_cm_modeldef;
	int user_cm_modelindex;
	string user_cm_modelpath;
	string user_cm_model;
	int user_cm_skinindex;
	string user_cm_skinpath;
	string user_cm_skin;
	int user_cm_flags; //Tip: if the flag (bit) value includes 2 (or just set it to 2) the model will be invisible
	//$UserDefaultValue -1
	int user_cm_generatorindex;
	int user_cm_animationindex;
	string user_cm_animationpath;
	string user_cm_animation;
}

//Ultimate Doom Builder doesn't need to read the rest
//$GZDB_SKIP

extend class FishyPlatformGeneric
{
	override void BeginPlay () //This gets called before any user vars are set - any atypical default values have to be set here
	{
		Super.BeginPlay();
		user_set_radius = -1; //Passing a negative value to A_SetSize() means "don't change"
		user_set_height = -1;
		user_cm_generatorindex = -1;
		//Will not set 'user_modelsetssize' to "true" here - so it doesn't affect maps before this was implemented
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

	private bool SetSizeFromModel ()
	{
		string fullName;
		if (user_cm_modelpath != "" &&
			user_cm_model != "" &&
			user_cm_modelpath.Mid(user_cm_modelpath.Length() - 1, 1) != "/") //The last character of *modelpath is not "/"?
		{
			fullName = user_cm_modelpath .. "/" .. user_cm_model;
		}
		else
		{
			fullName = user_cm_modelpath .. user_cm_model;
		}

		if (fullName == "")
			return false; //No abort exceptions if no model was provided

		int len = fullName.Length();
		if (len <= 4 || !(fullName.Mid(len - 4, 4) ~== ".obj"))
		{
			string why = (len <= 4) ? "it's too short." : "only .obj files can be parsed.";

			Console.Printf("\ckSetSizeFromModel(): invalid model: '" .. fullName .. "' " .. why ..
				"\n\ckPlatform position: " .. pos .. " tid: " .. tid .. "\n.");
			FishyDelayedAbort.Create(2, "SetSizeFromModel() errors.");
			return false;
		}

		int lump = Wads.CheckNumForFullName(fullName);
		if (lump < 0)
		{
			Console.Printf("\ckSetSizeFromModel(): invalid model: '" .. fullName .. "' can't be found." ..
				"\n\ckPlatform position: " .. pos .. " tid: " .. tid .. "\n.");
			FishyDelayedAbort.Create(2, "SetSizeFromModel() errors.");
			return false;
		}

		// Notes about the ScriptScanner:
		// bool GetString() advances the parser. It returns false when reaching the end of the file.
		// string GetStringContents() does NOT advance the parser.
		// void MustGetFloat() advances the parser.
		double newRad = 0;
		double newHi = 0;
		let sc = new("ScriptScanner");
		sc.OpenLumpNum(lump);
		while (sc.GetString())
		{
			if (sc.GetStringContents() ~== "v")
			{
				// WARNING
				// We're running with the assumption that this
				// .OBJ model is created from exported level geometry
				// WITH THE FOLLOWING OPTIONS CHECKED!
				// --Center model--
				// --Normalize lowest vertex z to 0--
				// --Ignore 3D floor control sectors--
				// (They are checked by default.)
				//
				// Having either "Center model"
				// or "Normalize lowest vertex z to 0" unchecked
				// produces undesired results!

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
}

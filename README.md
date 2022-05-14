# 3D platform
 Horizontally and vertically moving platform actor class for GZDoom.
 
 The main feature of the platform class is that it's able to carry other actors on top of itself.
 Possibilies include:
 - Old-fashioned platforming
 - Enemies that ride moving "cars" while attacking you.
 - Floors and ceilings opening up.
 - Any scenario at all where you can imagine a horizontally moving piece of "geometry"
 that you can stand on and be carried by.
 
 Movement is based on GZDoom's PathFollower. That is, it moves by using map placed
 interpolation points. But it can also be moved/rotated via ACS since it has dedicated
 ACS utility functions.
 
 A short demo map (MAP01) is included that demonstrates what's possible.
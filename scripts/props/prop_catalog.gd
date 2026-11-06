class_name PropCatalog
## Data for every prop. Adding a prop means adding one entry here.
##
## size:    collision box.
## The mesh is assets/models/props/<key>.glb.
## tool:    held like a club and rotated with the view.
## bonk:    knockout power (a dummy has 3 HP, bare fists do 1).

const DEFS := {
	&"coal": {
		"label": "coal", "mass": 2.0, "size": Vector3(0.26, 0.2, 0.24), "bonk": 1,
	},
	&"crate": {
		"label": "crate", "mass": 14.0, "size": Vector3(0.62, 0.5, 0.62), "bonk": 2,
	},
	&"suitcase": {
		"label": "suitcase", "mass": 8.0, "size": Vector3(0.62, 0.42, 0.22), "bonk": 2,
	},
	&"soup_bowl": {
		"label": "soup bowl", "mass": 0.7, "size": Vector3(0.26, 0.1, 0.26), "bonk": 1,
	},
	&"wrench": {
		"label": "wrench", "mass": 2.4, "size": Vector3(0.1, 0.05, 0.56), "bonk": 3, "tool": true,
	},
	&"frying_pan": {
		"label": "frying pan", "mass": 2.0, "size": Vector3(0.3, 0.06, 0.62), "bonk": 3, "tool": true,
	},
	&"broom": {
		"label": "broom", "mass": 1.4, "size": Vector3(0.28, 0.08, 1.35), "bonk": 1, "tool": true,
	},
}

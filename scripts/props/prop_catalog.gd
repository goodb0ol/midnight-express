class_name PropCatalog
## Data for every graybox prop. Adding a prop means adding one entry here.
##
## size:    collision box.
## parts:   visual boxes [size, offset, color]; defaults to the collision box.
## tool:    held like a club and rotated with the view.
## bonk:    knockout power (a dummy has 3 HP, bare fists do 1).

const DEFS := {
	&"coal": {
		"label": "coal", "mass": 2.0, "size": Vector3(0.26, 0.2, 0.24), "color": Color(0.08, 0.08, 0.09), "bonk": 1,
	},
	&"crate": {
		"label": "crate", "mass": 14.0, "size": Vector3(0.62, 0.5, 0.62), "color": Color(0.5, 0.36, 0.2), "bonk": 2,
	},
	&"suitcase": {
		"label": "suitcase", "mass": 8.0, "size": Vector3(0.62, 0.42, 0.22), "color": Color(0.45, 0.26, 0.14), "bonk": 2,
	},
	&"soup_bowl": {
		"label": "soup bowl", "mass": 0.7, "size": Vector3(0.26, 0.1, 0.26), "color": Color(0.85, 0.83, 0.75), "bonk": 1,
		"parts": [
			[Vector3(0.26, 0.1, 0.26), Vector3.ZERO, Color(0.85, 0.83, 0.75)],
			[Vector3(0.2, 0.012, 0.2), Vector3(0.0, 0.053, 0.0), Color(0.75, 0.5, 0.15)],
		],
	},
	&"wrench": {
		"label": "wrench", "mass": 2.4, "size": Vector3(0.1, 0.05, 0.56), "color": Color(0.5, 0.52, 0.56), "bonk": 3, "tool": true,
		"parts": [
			[Vector3(0.06, 0.05, 0.56), Vector3.ZERO, Color(0.5, 0.52, 0.56)],
			[Vector3(0.14, 0.05, 0.12), Vector3(0.0, 0.0, -0.26), Color(0.42, 0.44, 0.48)],
		],
	},
	&"frying_pan": {
		"label": "frying pan", "mass": 2.0, "size": Vector3(0.3, 0.06, 0.62), "color": Color(0.1, 0.1, 0.11), "bonk": 3, "tool": true,
		"parts": [
			[Vector3(0.3, 0.05, 0.3), Vector3(0.0, 0.0, -0.16), Color(0.12, 0.12, 0.13)],
			[Vector3(0.05, 0.04, 0.32), Vector3(0.0, 0.0, 0.15), Color(0.24, 0.16, 0.1)],
		],
	},
	&"broom": {
		"label": "broom", "mass": 1.4, "size": Vector3(0.28, 0.08, 1.35), "color": Color(0.6, 0.5, 0.3), "bonk": 1, "tool": true,
		"parts": [
			[Vector3(0.05, 0.05, 1.05), Vector3(0.0, 0.0, 0.15), Color(0.5, 0.36, 0.2)],
			[Vector3(0.28, 0.08, 0.3), Vector3(0.0, 0.0, -0.52), Color(0.75, 0.65, 0.35)],
		],
	},
}

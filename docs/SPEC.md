# Game Design & Technical Spec: The Midnight Express: Boiler & Bistro

## 1. High-Level Concept & Vibe
**Genre:** First-Person Co-op Physics Management, Inspection & Survival ("Jank-Core" / Stylized Low-Poly)
**Inspirations:** *Dear Passenger*, *Supermarket Together*, *Don't Starve Together*
**Target Platforms:** PC (Keyboard/Mouse) & Mobile (iOS/Android Touch) with cross-play parity.
**Engine:** Godot 4.x

**The Pitch:**
Players are the crew of a ramshackle steam train hurtling endlessly through a frozen, monster-infested wasteland. To survive and get rich, players must shovel coal into the boiler, run a chaotic bistro car serving questionable food to eccentric passengers, inspect IDs and luggage at border stations, smuggle high-paying contraband, and physically bonk and throw illegal passengers or contraband out the train windows at 100 km/h right before Border Patrol raids to avoid massive fines.

**Visual & Gameplay Tone:**
Lean into fast, tactile, slightly chaotic first-person physics ("AI-slop / viral co-op simulator" energy). Low-poly chunky models, uncanny passenger portraits, and full rigidbody interactions where every item (coal, soup bowls, wrenches, brooms, suitcases, and knocked-out passengers) can be picked up, carried, dropped, or chucked across the room.

---

## 2. The Core Physics Trick: "The Hybrid Velocity Zone"
We want the hilarious physics of throwing people and objects off a speeding train and watching them bounce down the snowy tracks, WITHOUT suffering from floating-point jitter or multiplayer physics desync inside the carriages.

1. **The Stationary Train (Interior Safe Zone):** The train itself sits completely still at world origin `(0, 0, 0)`. Walking, cooking, and stacking items inside the carriages happen in stable zero-velocity space.
2. **The Scrolling Wasteland Treadmill:** The exterior world (tracks, snowy ground, telegraph poles, trees, tunnels, and stations) scrolls backward past the train at the train's current speed. When the train stops at a station, the treadmill decelerates until the station platform aligns with the carriage doors.
3. **The Exterior Yeet Zone:** A trigger zone wraps the outside of all train windows, openable doors, and the rear caboose platform. The instant any physics object, suitcase, or ragdolled NPC crosses out of a window or door into the outside air, the game applies the train's backward speed to them so they hit the scrolling ground at high speed, ragdoll violently into passing obstacles, and disappear into the distance behind the train.
4. **Player Fall-Out Safety:** If a player falls out a door or window, they get dragged backward along the snow too, but a trailing emergency rope behind the caboose gives them a few seconds to grab on and pull themselves back aboard before getting left behind.

---

## 3. The 3-Phase Gameplay Loop

### Phase A: The Station Stop (Inspection, Smuggling & Restock)
When the train pulls into a station, a departure countdown begins.
- **The Boarding Gate (*Dear Passenger* loop):** A queue of procedurally generated weirdos lines up at the door. Players inspect their tickets, IDs, and faces against the daily rules on a clipboard (e.g., forged stamps, banned sectors, mutated traits) and optionally scan their luggage. Players can approve them, reject them, or take bribes to let illegal smugglers and banned cargo aboard.
- **The Platform Hustle (*Supermarket Together* loop):** Other players sprint onto the station platform to buy crates of raw food, coal, and repair parts, physically hauling them back onto the train before the whistle blows, or making shady deals with platform NPCs to hide high-value contraband inside the train's secret wall panels.

### Phase B: The Transit Rush (Hospitality & Engine Management)
Once the train leaves the station, the doors lock and real-time multitasking chaos begins across the carriages:
- **Car 1 - The Locomotive (Survival & Power):** The furnace constantly burns coal to maintain speed and cabin heat. Players must shovel coal, release boiler pressure valves, tighten rattling pipes with a wrench, and manage the breaker box that routes power between kitchen appliances, cabin heaters, and exterior floodlights.
- **Car 2 - The Galley & Bistro (Service & Cooking):** Seated passengers demand food and drinks via floating overhead icons. Players chop ingredients, grill mystery meat (which catches fire if neglected), pour drinks, carry plates down the swaying aisle, mop up puke/spills, and collect cash tips on tables.
- **Car 3 - Coach & Baggage (Crowd Control & Smuggling):** Passengers sleep, use the toilet (which frequently clogs and floods the aisle), and interact based on their procedural traits. Seating a rowdy drunk next to an aristocrat triggers fistfights that players must break up by bonking them with a broom or wrench.

### Phase C: Border Patrol Raids & Night Hazards (Emergency Defenestration)
Mid-transit, alarms or weather anomalies trigger high-stakes panic:
- **Border Patrol Drone/Guard Raid:** Sirens blare with a 30-to-45-second warning before the train is scanned or boarded. Any smuggled contraband or illegal undocumented passenger still inside the train triggers a massive cash fine.
- **The Cover-Up (Yeeting Passengers):** Players must sprint into the passenger cars, either hide contraband under floorboards OR bonk illegal passengers unconscious with a frying pan/wrench, drag their floppy ragdoll bodies to a window or side door, open it (which rapidly drops cabin temperature), and heave them out into the snow at 100 km/h.
- **The Witness System:** Normal passengers have a Shock Meter. If they witness you knocking out and defenestrating a passenger mid-dinner, they panic and run for the emergency brake lever, forcing your co-op partner to bribe them, lock them in the bathroom, or throw the witnesses out the window too.
- **The Deep Freeze & Night Terrors (*Don't Starve* loop):** If coal runs out or doors are left open at night, windows frost over, passengers freeze, lights flicker, and wasteland creatures latch onto the outside of the windows, requiring players to blast them off with flare guns or blowtorches.

---

## 4. Solo Grind vs. Co-op Chaos Progression
- **Train Depot & Expansion:** Between runs (or during chill solo play), players use their earned cash to buy new modular carriages that snap onto the back of the train (VIP Casino Car, Hydroponic Greenhouse Car, Smuggler's Hold, Automated Coal Conveyor), upgrade heaters, and organize stock.
- **Solo Mode:** Players can run shorter, safer daytime cargo/passenger routes and hire basic clockwork/NPC porters to help carry plates while focusing on train layout and automation.
- **Co-op Mode (2-4+ Players):** High-speed night contracts with long trains, VIP passengers, relentless border raids, and chaotic role-splitting where communication and panic drive the fun.

---

## 5. Cross-Platform Control Parity (PC + Mobile)
Keep interactions unified around a center-screen raycast and simple context actions so PC and Mobile play together seamlessly:
- **Movement & Camera:** WASD + Mouse on PC; Virtual Left Joystick + Right-Screen Touch Drag on Mobile (with subtle aim-magnetism toward interactables on touchscreens).
- **4 Core Actions:**
  1. **Grab / Interact / Drop:** Pick up any physics prop or ragdoll limb, open doors, flip switches, or place items on snap-surfaces.
  2. **Throw (Hold & Release):** Chuck held coal into the furnace, toss plates to a friend, or heave a smuggler out a window.
  3. **Use / Bonk:** Swing held tool (mop floor, wrench pipe, bonk unruly passenger, stamp passport).
  4. **Clipboard / Inspection UI:** Pull up the station manifest and ID inspection overlay.

---

## 6. Autonomous Build Roadmap for Claude Code
Please build this project iteratively in playable vertical slices:
1. **Milestone 1 (The Physics Boxcar & Yeet Prototype):** Set up the Godot project, PC/Mobile input mappings, the stationary 3-car graybox train with openable doors/windows, the scrolling exterior wasteland treadmill, the First-Person grab/throw/bonk controller, and the Exterior Yeet Zone so we can immediately test knocking out test-dummy NPCs and throwing them out of the speeding train.
2. **Milestone 2 (The Boiler & Bistro Loop):** Implement the coal furnace, train speed/temperature decay, breaker box, raw-to-cooked stove mechanics, and dirty plate cleanup.
3. **Milestone 3 (Station Stops & Passenger AI):** Implement the treadmill deceleration into station platforms, passenger spawning, the ID/luggage inspection UI, seating behavior, food ordering, and the Witness/Shock system when someone gets bonked.
4. **Milestone 4 (Border Raids & Multiplayer Sync):** Implement the Border Patrol raid countdown/fines, contraband hiding spots, and peer-to-peer co-op networking so multiple players can play together.

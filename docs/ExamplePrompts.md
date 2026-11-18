# Example Prompts

Example task prompts for the bin picking demo, grouped by the kind of reasoning they test. Expected results are for the shipped layout.

## Prompts

The six prompts from the README: three on color and shape, three on spatial reasoning.

| Prompt | Tests | Expected result |
|---|---|---|
| "Move the gray elbow to the right table. Move the green tee to the left table." | Color and shape | Gray elbow &rarr; right, green tee &rarr; left |
| "Move the crosses to the right table and the elbows to the left table." | Shape groups | Cyan and blue crosses &rarr; right, gray and magenta elbows &rarr; left |
| "Move every fitting that is not red or green to the left table." | Negation | Cyan cross, blue cross, magenta elbow, gray elbow &rarr; left |
| "Move the fitting surrounded by all the others to the left table." | Center of the group | Magenta elbow &rarr; left |
| "Move the red fittings to the table closer to the gray elbow." | Distance from another object to each table | Red straight and red tee &rarr; left |
| "Put the two fittings farthest apart on the table nearest to each." | Pairwise distances, then nearest table | Gray elbow &rarr; left, green tee &rarr; right |

## Color and Shape Reasoning

These prompts select fittings by color, shape, or both, including groups, exclusions, and counts.

| Prompt | Tests | Expected result |
|---|---|---|
| "Move the blue cross to the left table." | Single object, color and shape | Blue cross &rarr; left |
| "Move the magenta elbow to the right table. Move the red straight to the left table." | Two objects, two destinations | Magenta elbow &rarr; right, red straight &rarr; left |
| "Move the tees to the right table." | Shape group | Red tee, green tee &rarr; right |
| "Move all red fittings to the left table." | Color group | Red straight, red tee &rarr; left |
| "Move the tees to the left table and the crosses to the right table." | Two shape groups | Red and green tees &rarr; left, cyan and blue crosses &rarr; right |
| "Move the red tee to the left table and the green tee to the right table." | Same shape, different colors | Red tee &rarr; left, green tee &rarr; right |
| "Move every elbow and every straight to the right table." | Shape union | Magenta elbow, gray elbow, red straight, green straight &rarr; right |
| "Move the red fitting that is not a tee to the right table." | Color with shape exclusion | Red straight &rarr; right |
| "Move every fitting that is not a cross to the left table." | Shape negation | Red straight, green straight, red tee, green tee, magenta elbow, gray elbow &rarr; left |
| "Move every fitting except the gray elbow to the right table." | Single exception | All except gray elbow &rarr; right |
| "Move the only gray fitting to the left table." | Unique color | Gray elbow &rarr; left |
| "Move the fittings whose color appears more than once to the right table." | Counting by color | Red straight, red tee, green straight, green tee &rarr; right |
| "Move one fitting of each shape to the left table." | One per category | One straight, one tee, one cross, one elbow &rarr; left |
| "Move the cyan and blue fittings to the left table and the gray fitting to the right table." | Color list, mixed destinations | Cyan cross, blue cross &rarr; left, gray elbow &rarr; right |

## Spatial Reasoning

These prompts select fittings or destinations by position: extremes, distances, regions, and nearest tables.

| Prompt | Tests | Expected result |
|---|---|---|
| "Move the leftmost fitting to the left table." | Extreme position | Gray elbow &rarr; left |
| "Move the rightmost fitting to the right table and the leftmost fitting to the left table." | Two extremes | Green tee &rarr; right, gray elbow &rarr; left |
| "Move the fitting closest to the green tee to the right table." | Nearest neighbor | Blue cross &rarr; right (green straight is almost as close) |
| "Move the fitting farthest from the green tee to the left table." | Farthest from a reference | Gray elbow &rarr; left |
| "Move each fitting to the table nearest to it." | Per-object nearest table | Cyan cross, red straight, gray elbow &rarr; left; blue cross, green tee, red tee, green straight &rarr; right; magenta elbow (center) &rarr; either |
| "Move the gray elbow to the table farther from it." | Per-object farthest table | Gray elbow &rarr; right |
| "Move the red tee and the green straight to the right table." | Neighboring pair | Red tee, green straight &rarr; right |
| "Move every fitting on the left half of the bin to the right table." | Region selection | Cyan cross, red straight, gray elbow &rarr; right |
| "Move the fittings in the top row of the bin to the left table." | Row selection | Cyan cross, blue cross &rarr; left |
| "Move the crosses to the table closer to the red straight." | Destination by reference object | Cyan and blue crosses &rarr; left |
| "Move the fitting between the two crosses to the left table." | Betweenness | Magenta elbow &rarr; left |
| "Move the three fittings nearest to the center of the bin to the right table." | Distance ranking from a point | Magenta elbow, red tee, blue cross &rarr; right (cyan cross is almost as close) |
| "Swap sides: move the fittings near the left table to the right table and the fittings near the right table to the left table." | Mirrored nearest-table logic | Each fitting &rarr; its farther table |

## Combined Reasoning

These prompts chain a color or shape filter with spatial reasoning, ordering, or grouping constraints.

| Prompt | Tests | Expected result |
|---|---|---|
| "Move the leftmost tee to the right table." | Shape filter, then position | Red tee &rarr; right |
| "Move the elbow closest to a cross to the left table." | Shape filter, then distance | Magenta elbow &rarr; left |
| "Move the red fittings to the left table, then move the fitting closest to where they were to the right table." | Sequenced, reference after move | Red straight, red tee &rarr; left, then their nearest neighbor &rarr; right |
| "Move every fitting that is not red to the table nearest to it." | Negation and nearest table | Non-red fittings &rarr; nearest table |
| "Move the green fittings to the right table, picking the one closest to the robot first." | Pick order | Green straight first, then green tee &rarr; right |
| "Move all fittings to the left table, starting with the rightmost and ending with the leftmost." | Ordered by position | All &rarr; left, right-to-left order |
| "Move the straights to the table nearest to each of them." | Shape filter, then per-object nearest table | Red straight &rarr; left, green straight &rarr; right |
| "Split the fittings evenly: put half on the left table and half on the right table, keeping same-shape fittings together." | Grouping with balance constraint | Two shape groups per table, four fittings each |

## Placement on a Table

These prompts ask for a specific spot on a table, such as a corner, an edge, or the center. "Top", "bottom", "left" and "right" refer to the overhead camera image. The Task Verifier may not flag a part that lands on the correct table but off the requested spot.

| Prompt | Tests | Expected result |
|---|---|---|
| "Move the gray elbow to the top left corner of the right table, but keep enough margin so that the object does not fall down." | Corner with a safety margin | Gray elbow &rarr; right table, near the top left corner and fully on the table |
| "Place the green tee in the bottom right corner of the left table, leaving a small gap to the edges." | Opposite corner, other table | Green tee &rarr; left table, near the bottom right corner |
| "Put the red straight along the outer edge of the right table, away from the bin, without letting it overhang." | Edge placement, no overhang | Red straight &rarr; right table, near its outer edge |
| "Move the blue cross close to the edge of the left table that faces the bin, but not so close that it tips over." | Edge picked by reference to the bin | Blue cross &rarr; left table, near its bin-side edge |
| "Move the cyan cross to the exact center of the left table." | Center of a table | Cyan cross &rarr; left table, centered |
| "Put the red tee on the right table, then place the green tee directly above it in the image, with a gap between them." | Placement relative to another placed part | Red tee and green tee &rarr; right table, green tee above red tee, not touching |
| "Place the gray elbow in the top left corner and the magenta elbow in the bottom right corner of the left table, both safely away from the edges." | Two corners on one table | Gray elbow &rarr; top left, magenta elbow &rarr; bottom right of the left table |
| "Put one fitting in each corner of the right table, keeping all of them fully on the table." | Four corners, choice of parts | Four fittings &rarr; right table, one per corner |
| "Move the tees to the left table and place them as far apart as possible without either one falling off." | Maximize spacing under an edge constraint | Red and green tees &rarr; left table, at opposite ends with margin |

## Ambiguous and Edge-Case Prompts

Use these to probe how the Task Planner and Task Verifier handle prompts that are vague, impossible, or already satisfied. Results vary between runs.

| Prompt | Tests | Expected result |
|---|---|---|
| "Move the yellow fitting to the left table." | Nonexistent color | No objects selected; verifier reports failure or nothing to move |
| "Move the tee to the right table." | Ambiguous reference (two tees) | Model picks one or both tees |
| "Move the only straight fitting to the left table." | False premise (two straights) | Model picks one or both straights |
| "Move the biggest fitting to the left table." | Attribute not specified in scene | Model chooses by apparent size |
| "Move the fitting farthest from the magenta elbow to the left table." | Near-tie (gray elbow, green tee, green straight) | Any of the three &rarr; left |
| "Move the two fittings closest to each other to the right table." | Near-tie (red straight and gray elbow, red tee and green straight) | Either pair &rarr; right |
| "Clear the bin." | Underspecified destination | All fittings moved to one or both tables |
| "Move the elbows to the left table, but leave the gray one." | Correction within the prompt | Magenta elbow &rarr; left |
| "Do not move anything." | Null task | No objects selected |

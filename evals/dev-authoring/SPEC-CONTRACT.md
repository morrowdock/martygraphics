# Dev authoring eval: grading contract

This contract fixes what each check in [specs.json](specs.json) means. It was frozen together with the
requests and the specs, before any scene was authored ([FREEZE.json](FREEZE.json)). The grader implements
it; engine conventions (vector angles, incline geometry, plot mapping, step visibility) are mirrored from
the Swift sources, not from the author's documentation.

## Pass rules

- A request is **valid** when its final output passes the validator: core scenes through the copied
  `scene_v1_check.py` draft preflight (template expansion is deferred to Swift, as the checker reports),
  ML documents through the Python ML mirror. An invalid final output fails every check.
- A request is **mechanically correct** when it is valid and every check passes.
- Partial credit (checks passed / checks total) is reported but never replaces the binary result.
- Each check has a category: `items`, `geometry`, `direction`, `magnitude`, `numbers`, `data`, `order`.

## Bindings

`bind` names items by kind (`kind` list) and optional filters: `label_re` matches the item's own label or
the text of a `text` item whose anchor lies within 1.2 world units of the item's centre; `text_re`
matches a `node` or `text` item's `text`. Distinct bindings take distinct items. The grader searches all
assignments and keeps the one that passes the most checks (ties: earliest items in authored order), so
ids and item order never matter.

## Steps, states and presentation

- `S(-1)` is the authored item list. `S(k)` applies the `do` edits of steps 0…k in order, as the parser
  does (an edit replaces one key; setting a vector's `on` drops `from` and vice versa).
- `visible(X, k)` follows the engine timeline for step k.
- `rank(X)` is the first step that references X: X is in `show`, is the `focus`, is the `id` of an edit,
  or becomes a highlight `target` through an edit. If no step references X, `rank(X)` is the first step at
  which X is visible. `order` passes when the ranks strictly increase along `seq`.
- State-sequence checks walk the steps in order and collapse consecutive duplicates. The expected states
  must appear as a subsequence unless the check says `exact_final` (the last state must equal the last
  expected state) or `only` (no other state may appear).

## Geometry

Directions are degrees counter-clockwise from +x with y up. A vector's tail is its `from` point or the
centre of its `on` item, and its head is the tail plus `len` along its direction, both by engine
convention. `anchored` passes when the vector is `on` the item or its tail lies within the item's radius
(half the body size, or node/pulley radius) plus 0.3. `R(X)` below is that radius.

| Check | Passes when |
| --- | --- |
| `dir` | The vector's direction is within `tol` degrees of `deg`. |
| `dir_rel` | Direction within `tol` of: `incline_normal` (perpendicular to the slope, away from the solid), `incline_up` / `incline_down` (along the slope toward the high / low end), `toward_center` / `away_from_center` (the line from the tail to the reference centre), `tangent` (perpendicular to the radius from the reference centre to the tail, either sense). |
| `len_ratio` | `len(a) / len(b)` is within `rtol` (relative) of `ratio`. |
| `on_incline` | The body centre lies over the slope's horizontal extent and on the outward side at a perpendicular distance between 0.25 and 1.25 body sizes from the slope line. |
| `on_circle` | The item centre is at distance `r` (±`rtol`·r) from the orbit centre. |
| `left_right`, `below`, `above` | Compare item centres (x for left/right, y for above/below). |
| `horizontal` | A line's direction is within `tol` degrees of horizontal. |
| `spring_connects` | One spring end lies within 0.3 of the top line segment and the other within R(bottom)+0.35 of the bottom item's centre. |
| `rope_attached` | Each listed item has an item of the given kinds with an endpoint within R+0.4 of its centre. |
| `count` | At least `min` items of `kind`. |
| `circle_point` | An item of `kinds` sits at centre + r·(cos deg, sin deg) within `rtol`·r. It becomes point `P`. |
| `segment` | An item of `kinds` (line, path or vector; `dashed` if required) has its two ends within `dist_frac`·r of the two named points, in either order. Points: `center:<b>`, `P`, `projx:P` = (P.x, centre y), `projy:P` = (centre x, P.y). |
| `axes_at_center` | An `axes` item's origin, or the crossing of a horizontal and a vertical line, lies within `tol_frac`·r of the circle centre. |
| `head_to_tail` | tail(second) is within `tol_frac`·len(first) of head(first). `same_tail` / `same_head` compare tails / heads the same way. |
| `triangle` | A region of 3 points, a path of 3 points or 4 closed points, or 3 lines sharing ends (within 0.1) has side lengths proportional to `sides` (±`rtol`) and a right angle (±`right_tol` degrees) opposite the longest side. |
| `side_labels` | For each side, a text item (or the label of a line on that side) contains the side's number and lies within `dist` of the side's midpoint. |
| `right_angle_mark` | Some other item has an anchor point within `dist` of the right-angle vertex. |
| `near_plot_point` | Some item of `kinds` (not the plot) has an anchor within `dist` of the world position of data point `xy` in plot `plot`. |
| `plot_segment` | Some item of `kinds` has its ends within `dist` of the world positions of data points `from` and `to`. |
| `snell_setup` | A horizontal line (±3°) is the surface, and a vertical line, path or vector (±3°) crosses it; rays meet at an entry point on the surface within 0.3. |
| `snell_angles` | The ray above the surface meets the normal at `incident` ± `tol` degrees, the ray below at `refracted` ± `tol`, on opposite sides of the normal. |
| `seesaw_dist` | A near-horizontal line (±5°) is the beam; a pivot item's top point is within 0.6 of the beam between two bodies on opposite sides; the heavy child's distance to the pivot over the light child's is `ratio` ± `rtol`. The heavy child is the one with the longer down arrow. |
| `pend_*` | The string is a line, rope or path with one end fixed over all states (the pivot) and the other within 0.35·size + 0.15 of the bob in every state (`pend_string_attached`). The first bob state hangs straight down ±`tol` (`pend_rest_first`); later states reach `deg` ± `tol` on both sides of vertical (`pend_extremes`); bob–pivot distance stays within `rtol` (`pend_length_constant`). |

## Data

| Check | Passes when |
| --- | --- |
| `field` | The authored field equals `eq` (numbers within `tol`). |
| `plot_fn` | Every authored point satisfies \|y − f(x)\| ≤ `atol`; at least `min_pts` points; the points span `x_span` within `span_tol`. `f` uses `x`, + − * / **, sin, cos, sqrt, pi, min, max, abs. |
| `plot_has_points` | Each listed data point is an authored point within `tol`. |
| `plot_box` | The plot's `xr` / `yr` contain the listed x / y extents (1 % span slack). |
| `rects` | A bars item has values equal to `heights` (±`rtol` absolute, in order), or region rectangles of equal width have heights proportional to the nonzero heights. |
| `bars_values` | Bar values in authored order equal (`exact`) or are proportional to (`proportional`) `values` within `rtol`, with exactly that many bars. |
| `bars_labels_order` | Bar *i*'s label contains the listed token as a whole word. |
| `bars_labeled_values` | Each class regex matches exactly one bar label and that bar's value is `v` ± `rtol`. |
| `bars_states` | Over the steps, a visible bars item whose labels match the role regexes takes the listed role values (±`rtol`·max) in order. |
| `array_vals` | An array state (`any`) or the final state (`final`) equals `vals` (cells compared as normalised text: trimmed, Unicode minus as `-`, numbers in shortest form). |
| `array_states` | The array's state sequence contains `states`; `strip` removes placeholder cells (empty, `-`, `–`, `—`, `_`, `.`, `·`, `∅`, `empty`, `null`, `nil`). |
| `stack_states` | Like `array_states` after ordering cells bottom to top: the `top` pointer must point at the last (or, reversed, the first) non-placeholder cell. |
| `ptr_states` | For each state, pointers whose label fully matches a role regex give role → index; the sequence contains the listed role maps. |
| `marked_states`, `marked_final` | The `marked` sets over the states contain `sets` in order / the final set equals `set`. |
| `table_rows` | Row 0 matches `header_re` cell by cell; the other rows equal `rows` (as a multiset unless `ordered`). |
| `table_marked_rows` | Every data row equal to a `marked` row has a marked cell; no row equal to an `unmarked` row does. |
| `graph_edges` | At the first step (`first`) or the final step (`final`), the visible edges between nodes (named by node text) equal `edges` (`exact`), as unordered pairs unless `directed` (then `dir: true` from `a` to `b`). |
| `visit_order` | Each step's visit signals (its focus node, nodes newly targeted by visible highlights, nodes whose colour an edit changes) give first visits in exactly the order of `nodes`, one new node per step. |
| `edge_order` | The first step with directed edge `first` comes before the first step with directed edge `then`. |
| `hash_final` | In the final state, the array of `n` cells (or table of `n` data rows) holds exactly the listed integers per bucket and none elsewhere. |
| `hash_order` | The first state containing each key follows the listed insertion order, one key per step. |
| `pie` | Region sectors around one centre have central angles of share·3.6° ± `deg_tol`, or a bars item is proportional to the shares (±`bars_rtol`) and the title, a text item or the narration matches `disclosure_re`. |
| `vec_states` | Among vectors pointing `dir` ± `tol`, the first visible one (at its first visible step) and one visible at a later step have length ratio `ratio` ± `rtol`. |
| `template` | `template` equals `name` and `params` deep-equal the listed values. |
| `steps` | The authored step count lies in [`min`, `max`]. |

## Text and numbers

Scopes: `say` (narration, from step `min_step`), `say_last` (the last step), `title`, `labels` (item labels,
text items, node text, bar labels and unit, axis labels, pointer labels, array and table cells), `label:<b>`
(the binding's label and text items within 1.2 of its tail, head, midpoint or centre), `any` (all of them).
Numbers are read with an optional sign (`-` or `−`), thousands separators, decimals, fractions `a/b`
(each part and the quotient), π forms (`π/2`, `3π/2`, `2pi`) and a trailing `kN`/`kJ` (× 1000).
`num` passes when some number in scope is within `rtol` (relative, default 0.01) or `atol` of a listed
value. `regex` passes when the pattern matches some text in scope (case-insensitive when `i` is set).

## ML documents

`ml_kind` selects the first item of that kind. `ml_field` compares an authored field, `ml_absent` requires
keys to be absent, `ml_optional_eq` allows a key to be absent or equal, `ml_candidates` compares the
token → logit map, `ml_points_labels` / `ml_cluster` / `ml_states` compare label or state sets, `ml_steps_candidates` fixes the
candidate count per step, `ml_map_groups` requires each point's nearest neighbour (Euclidean, authored
positions) to be in its own group, and `ml_fact` compares a value computed by the ML mirror
(`patchCount`, `chosen`, `retained`, `generated`, `minimumApprovalSteps`).

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { extractLottieIntent } from './extract-intent.mjs';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const oracleRoot = path.dirname(scriptDirectory);
const repoRoot = path.dirname(path.dirname(oracleRoot));
const fixturesRoot = path.join(repoRoot, 'Tests/Fixtures/LottieOracle');
const intentRoot = path.join(fixturesRoot, 'lottie-web-intent');
const skipIntent = process.argv.includes('--skip-intent');

const colors = {
  blue: [0.1, 0.4, 1, 1],
  red: [0.95, 0.15, 0.2, 1],
  teal: [0.05, 0.72, 0.65, 1],
  purple: [0.45, 0.25, 0.95, 1],
  amber: [1, 0.62, 0.12, 1],
  ink: [0.04, 0.05, 0.08, 1],
  gray: [0.78, 0.8, 0.84, 1]
};

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
}

function fixed(value, ix = 1) {
  return { a: 0, k: value, ix };
}

function easing(x1 = 0.333, y1 = 0.333, x2 = 0.667, y2 = 0.667) {
  return {
    i: { x: [x2], y: [y2] },
    o: { x: [x1], y: [y1] }
  };
}

function keyframedVector(start, end, startFrame = 0, endFrame = 9, ix = 2, curve = easing()) {
  return {
    a: 1,
    k: [
      { t: startFrame, s: start, e: end, ...curve },
      { t: endFrame, s: end }
    ],
    ix
  };
}

function keyframedScalar(start, end, startFrame = 0, endFrame = 9, ix = 10, curve = easing()) {
  return {
    a: 1,
    k: [
      { t: startFrame, s: [start], e: [end], ...curve },
      { t: endFrame, s: [end] }
    ],
    ix
  };
}

function fixedTransform(overrides = {}) {
  return {
    a: overrides.a ?? fixed([0, 0, 0], 1),
    p: overrides.p ?? fixed([0, 0, 0], 2),
    s: overrides.s ?? fixed([100, 100, 100], 6),
    r: overrides.r ?? fixed(0, 10),
    o: overrides.o ?? fixed(100, 11),
    ...overrides.extra
  };
}

function groupTransform(overrides = {}) {
  return {
    ty: 'tr',
    nm: 'Transform',
    p: overrides.p ?? fixed([0, 0], 2),
    a: overrides.a ?? fixed([0, 0], 1),
    s: overrides.s ?? fixed([100, 100], 3),
    r: overrides.r ?? fixed(0, 6),
    o: overrides.o ?? fixed(100, 7)
  };
}

function composition(name, layers, assets = []) {
  return {
    v: '5.7.4',
    nm: name,
    fr: 10,
    ip: 0,
    op: 10,
    w: 64,
    h: 64,
    assets,
    layers
  };
}

function shapeLayer(ind, name, shapes, options = {}) {
  return {
    ddd: options.ddd ?? 0,
    ind,
    ty: 4,
    nm: name,
    parent: options.parent,
    td: options.trackMatteSource,
    tt: options.trackMatteType,
    tp: options.trackMatteParent,
    ks: fixedTransform(options.transform),
    ao: options.autoOrient,
    shapes,
    masksProperties: options.masks,
    ip: options.ip ?? 0,
    op: options.op ?? 10,
    st: options.st ?? 0,
    bm: options.blendMode,
    sr: options.stretch ?? 1
  };
}

function nullLayer(ind, name, options = {}) {
  return {
    ddd: options.ddd ?? 0,
    ind,
    ty: 3,
    nm: name,
    parent: options.parent,
    ks: fixedTransform(options.transform),
    ao: options.autoOrient,
    ip: options.ip ?? 0,
    op: options.op ?? 10,
    st: options.st ?? 0,
    bm: options.blendMode,
    sr: options.stretch ?? 1
  };
}

function precompLayer(ind, name, referenceId, options = {}) {
  return {
    ddd: 0,
    ind,
    ty: 0,
    nm: name,
    refId: referenceId,
    w: options.width ?? 64,
    h: options.height ?? 64,
    ks: fixedTransform(options.transform),
    tm: options.timeRemap,
    ao: options.autoOrient,
    ip: options.ip ?? 0,
    op: options.op ?? 10,
    st: options.st ?? 0,
    bm: options.blendMode,
    sr: options.stretch ?? 1
  };
}

function group(name, items, transform = {}) {
  return {
    ty: 'gr',
    nm: name,
    np: items.length + 1,
    cix: 2,
    ix: 1,
    mn: 'ADBE Vector Group',
    hd: false,
    it: [...items, groupTransform(transform)]
  };
}

function rect(name, center = [32, 32], size = [24, 24], roundness = 0, direction = 1) {
  return {
    ty: 'rc',
    d: direction,
    nm: name,
    mn: 'ADBE Vector Shape - Rect',
    hd: false,
    ix: 1,
    p: fixed(center, 3),
    s: fixed(size, 2),
    r: fixed(roundness, 4)
  };
}

function ellipse(name, center = [32, 32], size = [24, 24], direction = 1) {
  return {
    ty: 'el',
    d: direction,
    nm: name,
    mn: 'ADBE Vector Shape - Ellipse',
    hd: false,
    ix: 1,
    p: fixed(center, 3),
    s: fixed(size, 2)
  };
}

function pathShape(name, vertices, inTangents, outTangents, closed = true, direction = 1) {
  return {
    ty: 'sh',
    d: direction,
    nm: name,
    hd: false,
    ix: 1,
    ks: fixed({
      i: inTangents,
      o: outTangents,
      v: vertices,
      c: closed
    }, 2)
  };
}

function polystar(name, starType, points, position, outerRadius, options = {}) {
  const shape = {
    ty: 'sr',
    nm: name,
    sy: starType,
    d: options.direction ?? 1,
    pt: fixed(points, 3),
    p: fixed(position, 4),
    r: fixed(options.rotation ?? 0, 5),
    or: fixed(outerRadius, 7),
    os: fixed(options.outerRoundness ?? 0, 8),
    ix: 1,
    mn: starType === 1 ? 'ADBE Vector Shape - Star' : 'ADBE Vector Shape - Polygon',
    hd: false
  };
  if (starType === 1) {
    shape.ir = fixed(options.innerRadius ?? outerRadius / 2, 9);
    shape.is = fixed(options.innerRoundness ?? 0, 10);
  }
  return shape;
}

function fill(name, color, opacity = 100, fillRule = 1) {
  return {
    ty: 'fl',
    nm: name,
    mn: 'ADBE Vector Graphic - Fill',
    hd: false,
    c: fixed(color, 4),
    o: typeof opacity === 'number' ? fixed(opacity, 5) : opacity,
    r: fillRule
  };
}

function stroke(name, color, width = 3, options = {}) {
  return {
    ty: 'st',
    nm: name,
    mn: 'ADBE Vector Graphic - Stroke',
    hd: false,
    c: fixed(color, 3),
    o: options.opacity ?? fixed(100, 4),
    w: typeof width === 'number' ? fixed(width, 5) : width,
    lc: options.lineCap ?? 1,
    lj: options.lineJoin ?? 1,
    ml: options.miterLimit ?? 4,
    d: options.dashPattern
  };
}

function trim(name, start, end, offset = 0, multiple = 1) {
  return {
    ty: 'tm',
    nm: name,
    s: typeof start === 'number' ? fixed(start, 1) : start,
    e: typeof end === 'number' ? fixed(end, 2) : end,
    o: typeof offset === 'number' ? fixed(offset, 3) : offset,
    m: multiple,
    ix: 1
  };
}

function mask(name, vertices, inverted = false, mode = 'a') {
  return {
    inv: inverted,
    mode,
    pt: fixed({
      i: vertices.map(() => [0, 0]),
      o: vertices.map(() => [0, 0]),
      v: vertices,
      c: true
    }, 1),
    o: fixed(100, 2),
    x: fixed(0, 3),
    nm: name
  };
}

function rectGroup(color = colors.blue, rectangle = rect('Box')) {
  return group('Box Group', [rectangle, fill('Fill', color)]);
}

function linePath(name = 'Line') {
  return pathShape(name, [[14, 32], [50, 32]], [[0, 0], [0, 0]], [[0, 0], [0, 0]], false);
}

function selectedFrames(kind = 'standard') {
  if (kind === 'window') {
    return [
      { frame: 2, rationale: 'Frame before the gated layer in-point proves ordinary content is still absent before ip.' },
      { frame: 3, rationale: 'Frame at the gated layer in-point proves Lottie uses ip inclusively.' },
      { frame: 8, rationale: 'Frame at the gated layer out-point proves Lottie uses op exclusively.' },
      { frame: 9, rationale: 'Last root frame proves the background remains after the gated layer leaves.' }
    ];
  }
  return [
    { frame: 0, rationale: 'First root source frame records the authored initial state.' },
    { frame: 5, rationale: 'Interior source frame catches interpolation and transform composition errors.' },
    { frame: 9, rationale: 'Last integer source frame before exclusive op=10 checks the end boundary.' }
  ];
}

function fixture(id, description, bugClass, coverage, document, options = {}) {
  return {
    id,
    description,
    bugClass,
    coverage,
    semanticStatus: options.semanticStatus ?? 'modeled',
    lottie: `../../Tests/Fixtures/LottieOracle/${id}.json`,
    lottieWebIntent: `../../Tests/Fixtures/LottieOracle/lottie-web-intent/${id}.json`,
    frames: options.frames ?? selectedFrames(),
    scale: 1,
    renderer: 'svg',
    expectReferenceNonEmpty: options.expectReferenceNonEmpty ?? true,
    expectedValidationEligible: options.expectedValidationEligible ?? options.semanticStatus !== 'diagnosed',
    document
  };
}

function fixtures() {
  const triangle = pathShape(
    'Triangle',
    [[32, 14], [50, 50], [14, 50]],
    [[0, 0], [0, 0], [0, 0]],
    [[0, 0], [0, 0], [0, 0]],
    true
  );
  const cubic = pathShape(
    'Cubic Open Path',
    [[12, 50], [52, 14]],
    [[0, 0], [-18, 28]],
    [[18, -28], [0, 0]],
    false
  );
  const bowTie = pathShape(
    'Bow Tie',
    [[18, 18], [46, 46], [46, 18], [18, 46]],
    [[0, 0], [0, 0], [0, 0], [0, 0]],
    [[0, 0], [0, 0], [0, 0], [0, 0]],
    true
  );
  const precompChild = shapeLayer(1, 'Precomp Box', [rectGroup(colors.teal, rect('Precomp Rect', [32, 32], [22, 22]))], {
    transform: { p: keyframedVector([0, 0, 0], [10, 0, 0], 0, 9) }
  });
  const precompAsset = {
    id: 'box_precomp',
    nm: 'Box Precomp',
    w: 64,
    h: 64,
    layers: [precompChild]
  };

  return [
    fixture(
      'eligible-shape-position',
      'Shape layer with one filled rectangle and animated layer position.',
      'Animated layer position was previously judged from shifted PNGs instead of numeric translation.',
      ['animated-position', 'rectangle', 'fill', 'transform'],
      composition('Oracle Eligible Shape Position', [
        shapeLayer(1, 'Moving Box', [rectGroup(colors.blue, rect('Box', [32, 32], [24, 24]))], {
          transform: { p: keyframedVector([0, 0, 0], [8, 0, 0], 0, 9, 2, easing(0.333, 0, 0.667, 1)) }
        })
      ])
    ),
    fixture(
      'static-rectangle-fill',
      'Static centered rectangle with a solid fill.',
      'Baseline geometry and fill color must be correct before animation is considered.',
      ['static-position', 'rectangle', 'fill'],
      composition('Static Rectangle Fill', [
        shapeLayer(1, 'Static Box', [rectGroup(colors.red, rect('Box', [32, 32], [30, 18]))])
      ])
    ),
    fixture(
      'animated-position-linear',
      'Rectangle with a linear animated layer position.',
      'Linear position in-betweens must match source-frame interpolation, not image inspection.',
      ['animated-position', 'rectangle', 'fill', 'transform'],
      composition('Animated Position Linear', [
        shapeLayer(1, 'Linear Box', [rectGroup(colors.teal)], {
          transform: { p: keyframedVector([0, 0, 0], [16, 8, 0], 0, 9) }
        })
      ])
    ),
    fixture(
      'split-position-ellipse',
      'Ellipse whose position is authored as split x and y properties.',
      'Split-position values must rejoin into one evaluated layer position before lowering.',
      ['split-position', 'ellipse', 'fill', 'transform'],
      composition('Split Position Ellipse', [
        shapeLayer(1, 'Split Ellipse', [group('Ellipse Group', [ellipse('Dot', [0, 0], [16, 16]), fill('Fill', colors.purple)])], {
          transform: {
            p: {
              s: true,
              x: keyframedScalar(18, 46, 0, 9, 2),
              y: fixed(32, 3),
              z: fixed(0, 4)
            }
          }
        })
      ])
    ),
    fixture(
      'anchor-rotation-rectangle',
      'Rectangle rotated around its center by an explicit layer anchor.',
      'Anchor translation and clockwise rotation order must agree with lottie-web matrices.',
      ['anchor', 'rotation', 'rectangle', 'fill'],
      composition('Anchor Rotation Rectangle', [
        shapeLayer(1, 'Anchored Box', [rectGroup(colors.amber)], {
          transform: { a: fixed([32, 32, 0], 1), p: fixed([32, 32, 0], 2), r: fixed(45, 10) }
        })
      ])
    ),
    fixture(
      'scale-rotation-anchor',
      'Rectangle with anchor, non-uniform scale, and rotation.',
      'Scale, anchor, and rotation composition must be measurable before target backend assignment.',
      ['anchor', 'scale', 'rotation', 'rectangle'],
      composition('Scale Rotation Anchor', [
        shapeLayer(1, 'Scaled Rotated Box', [rectGroup(colors.blue)], {
          transform: {
            a: fixed([32, 32, 0], 1),
            p: fixed([32, 32, 0], 2),
            s: fixed([125, 75, 100], 6),
            r: fixed(30, 10)
          }
        })
      ])
    ),
    fixture(
      'animated-opacity-rectangle',
      'Rectangle with animated layer opacity.',
      'Opacity must be sampled numerically at the source frame, not inferred from raster alpha by eye.',
      ['opacity', 'rectangle', 'fill'],
      composition('Animated Opacity Rectangle', [
        shapeLayer(1, 'Fading Box', [rectGroup(colors.purple)], {
          transform: { o: keyframedScalar(25, 100, 0, 9, 11) }
        })
      ])
    ),
    fixture(
      'group-transform-rectangle',
      'Shape group transform translates and rotates a rectangle inside a layer.',
      'Shape transforms are scoped to the group and must not be mistaken for layer transforms.',
      ['shape-transform', 'rectangle', 'fill'],
      composition('Group Transform Rectangle', [
        shapeLayer(1, 'Group Transform Box', [
          group('Moved Group', [rect('Box', [32, 32], [22, 18]), fill('Fill', colors.teal)], {
            p: fixed([8, 4], 2),
            r: fixed(15, 6)
          })
        ])
      ])
    ),
    fixture(
      'group-opacity-two-shapes',
      'A transparency group contains two filled shapes with group opacity.',
      'Group opacity is an atomic compositing fact and must not be flattened silently per shape.',
      ['shape-group', 'group-opacity', 'rectangle', 'ellipse'],
      composition('Group Opacity Two Shapes', [
        shapeLayer(1, 'Opacity Group', [
          group('Half Alpha Group', [
            rect('Left Box', [24, 32], [18, 18]),
            ellipse('Right Dot', [42, 32], [18, 18]),
            fill('Fill', colors.red)
          ], { o: fixed(50, 7) })
        ])
      ])
    ),
    fixture(
      'parent-null-transform-child',
      'Shape layer parented to a visible null transform carrier.',
      'Parent transform composition must use the parent layer matrix before the child matrix.',
      ['parent-transform', 'null-layer', 'rectangle', 'fill'],
      composition('Parent Null Transform Child', [
        shapeLayer(2, 'Child Box', [rectGroup(colors.blue)], { parent: 1 }),
        nullLayer(1, 'Parent Null', {
          transform: { p: fixed([8, 4, 0], 2), a: fixed([32, 32, 0], 1), r: fixed(15, 10) }
        })
      ])
    ),
    fixture(
      'parent-animated-transform-child',
      'Shape layer inherits an animated parent null position.',
      'Animated parent matrices must affect the child world matrix at every sampled frame.',
      ['parent-transform', 'animated-position', 'null-layer', 'rectangle'],
      composition('Parent Animated Transform Child', [
        shapeLayer(2, 'Child Box', [rectGroup(colors.teal)], { parent: 1 }),
        nullLayer(1, 'Animated Parent', {
          transform: { p: keyframedVector([0, 0, 0], [12, 8, 0], 0, 9) }
        })
      ])
    ),
    fixture(
      'ellipse-fill',
      'Static filled ellipse centered in the composition.',
      'Ellipse noon-start geometry and bounds must be captured in source space.',
      ['ellipse', 'fill'],
      composition('Ellipse Fill', [
        shapeLayer(1, 'Ellipse', [group('Ellipse Group', [ellipse('Oval', [32, 32], [28, 20]), fill('Fill', colors.amber)])])
      ])
    ),
    fixture(
      'ellipse-reversed-direction',
      'Ellipse with reversed direction flag.',
      'Direction changes trim and path ordering even when the untrimmed bounds look identical.',
      ['ellipse', 'direction', 'fill'],
      composition('Ellipse Reversed Direction', [
        shapeLayer(1, 'Reverse Ellipse', [group('Ellipse Group', [ellipse('Reverse Oval', [32, 32], [28, 20], 3), fill('Fill', colors.teal)])])
      ])
    ),
    fixture(
      'rounded-rectangle',
      'Rounded rectangle with non-zero roundness.',
      'Rounded rectangle control points require the lottie-web radius clamp and roundCorner constant.',
      ['rectangle', 'roundness', 'fill'],
      composition('Rounded Rectangle', [
        shapeLayer(1, 'Rounded Box', [rectGroup(colors.purple, rect('Rounded Box', [32, 32], [34, 22], 6))])
      ])
    ),
    fixture(
      'raw-bezier-triangle',
      'Closed authored Bezier triangle path with a fill.',
      'Raw path vertices and tangents must be preserved without primitive regeneration.',
      ['path', 'fill'],
      composition('Raw Bezier Triangle', [
        shapeLayer(1, 'Triangle', [group('Triangle Group', [triangle, fill('Fill', colors.red)])])
      ])
    ),
    fixture(
      'raw-bezier-cubic',
      'Open cubic Bezier path with a stroke.',
      'Cubic path length and bounds must come from authored tangents, not a polyline guess.',
      ['path', 'stroke'],
      composition('Raw Bezier Cubic', [
        shapeLayer(1, 'Cubic Stroke', [group('Cubic Group', [cubic, stroke('Stroke', colors.blue, 4, { lineCap: 2, lineJoin: 2 })])])
      ])
    ),
    fixture(
      'polygon-five',
      'Five-point polygon generated by the polystar primitive.',
      'Polygon point flooring, rotation, and direction must match lottie-web source geometry.',
      ['polygon', 'polystar', 'fill'],
      composition('Polygon Five', [
        shapeLayer(1, 'Polygon', [group('Polygon Group', [polystar('Pentagon', 2, 5, [32, 32], 18, { rotation: 18 }), fill('Fill', colors.teal)])])
      ])
    ),
    fixture(
      'star-five',
      'Five-point star generated by the polystar primitive.',
      'Star inner and outer radii must survive source evaluation before any PureDraw lowering.',
      ['star', 'polystar', 'fill'],
      composition('Star Five', [
        shapeLayer(1, 'Star', [group('Star Group', [polystar('Star', 1, 5, [32, 32], 20, { innerRadius: 8, rotation: -18 }), fill('Fill', colors.amber)])])
      ])
    ),
    fixture(
      'fill-rule-evenodd',
      'Self-intersecting filled path using the even-odd fill rule.',
      'Fill-rule style facts must be retained because identical vertices can rasterize differently.',
      ['path', 'fill-rule', 'fill'],
      composition('Fill Rule Even Odd', [
        shapeLayer(1, 'Even Odd Path', [group('Bow Tie Group', [bowTie, fill('Even Odd Fill', colors.purple, 100, 2)])])
      ])
    ),
    fixture(
      'stroke-basic-line',
      'Open line path with a simple stroke.',
      'Stroke color, opacity, and width must be measured as style facts separate from fill.',
      ['path', 'stroke'],
      composition('Stroke Basic Line', [
        shapeLayer(1, 'Line', [group('Line Group', [linePath(), stroke('Stroke', colors.ink, 4)])])
      ])
    ),
    fixture(
      'stroke-caps-joins',
      'Open angled path with round caps and joins.',
      'Line caps and joins are render-affecting stroke facts and must not disappear from the trace.',
      ['path', 'stroke', 'line-cap', 'line-join'],
      composition('Stroke Caps Joins', [
        shapeLayer(1, 'Round Stroke', [
          group('Angled Group', [
            pathShape('Angle', [[14, 48], [32, 16], [50, 48]], [[0, 0], [0, 0], [0, 0]], [[0, 0], [0, 0], [0, 0]], false),
            stroke('Round Stroke', colors.red, 5, { lineCap: 2, lineJoin: 2 })
          ])
        ])
      ])
    ),
    fixture(
      'stroke-dash',
      'Open line path with dash, gap, and offset entries.',
      'Dash arrays are numeric stroke facts and must be represented or reported before pixels.',
      ['path', 'stroke', 'dash'],
      composition('Stroke Dash', [
        shapeLayer(1, 'Dashed Line', [
          group('Dash Group', [
            linePath(),
            stroke('Dashed Stroke', colors.blue, 4, {
              dashPattern: [
                { n: 'd', nm: 'dash', v: fixed(6, 1) },
                { n: 'g', nm: 'gap', v: fixed(3, 2) },
                { n: 'o', nm: 'offset', v: fixed(2, 3) }
              ]
            })
          ])
        ])
      ])
    ),
    fixture(
      'animated-stroke-width',
      'Stroke width animated from thin to thick.',
      'Animated stroke width must be sampled from source frames before lowerer decisions.',
      ['path', 'stroke', 'animated-width'],
      composition('Animated Stroke Width', [
        shapeLayer(1, 'Growing Stroke', [group('Stroke Group', [linePath(), stroke('Animated Stroke', colors.teal, keyframedScalar(1, 8, 0, 9, 5))])])
      ])
    ),
    fixture(
      'trim-rectangle-half',
      'Rectangle stroke trimmed to the first half of its contour.',
      'Trim start/end percentages must map to contour length, not an arbitrary quadrant guess.',
      ['rectangle', 'stroke', 'trim'],
      composition('Trim Rectangle Half', [
        shapeLayer(1, 'Trimmed Rectangle', [group('Trim Group', [rect('Box', [32, 32], [28, 20]), trim('Trim Half', 0, 50), stroke('Stroke', colors.red, 4)])])
      ])
    ),
    fixture(
      'trim-ellipse-quadrant',
      'Ellipse stroke trimmed to the first quarter of its contour.',
      'Ellipse trim direction and noon-start ordering must be measurable numerically.',
      ['ellipse', 'stroke', 'trim'],
      composition('Trim Ellipse Quadrant', [
        shapeLayer(1, 'Trimmed Ellipse', [group('Trim Group', [ellipse('Oval', [32, 32], [30, 22]), trim('Trim Quarter', 0, 25), stroke('Stroke', colors.purple, 4)])])
      ])
    ),
    fixture(
      'animated-trim-path',
      'Line stroke whose trim end animates from zero to full length.',
      'Animated trim must produce source-frame segment facts before rendered output is trusted.',
      ['path', 'stroke', 'trim', 'animated-trim'],
      composition('Animated Trim Path', [
        shapeLayer(1, 'Animated Trim', [group('Trim Group', [linePath(), trim('Growing Trim', 0, keyframedScalar(0, 100, 0, 9, 2)), stroke('Stroke', colors.amber, 4)])])
      ])
    ),
    fixture(
      'layer-window-in-out',
      'A foreground layer appears only inside its half-open frame window.',
      'Layer ip/op semantics must be proven at numeric frame boundaries.',
      ['frame-window', 'rectangle', 'fill'],
      composition('Layer Window In Out', [
        shapeLayer(1, 'Windowed Box', [rectGroup(colors.red, rect('Windowed Box', [32, 32], [22, 22]))], { ip: 3, op: 8 }),
        shapeLayer(2, 'Background Box', [rectGroup(colors.gray, rect('Background', [32, 32], [44, 44]))])
      ]),
      { frames: selectedFrames('window') }
    ),
    fixture(
      'mask-add-rectangle',
      'Additive rectangular mask clips a filled rectangle layer.',
      'Mask path, mode, inversion, and opacity are source graph facts before backend masking.',
      ['mask', 'rectangle', 'fill'],
      composition('Mask Add Rectangle', [
        shapeLayer(1, 'Masked Box', [rectGroup(colors.blue, rect('Masked Box', [32, 32], [40, 30]))], {
          masks: [mask('Left Half Mask', [[12, 12], [34, 12], [34, 52], [12, 52]])]
        })
      ])
    ),
    fixture(
      'alpha-matte-rectangle',
      'Alpha matte layer clips the target rectangle.',
      'Track matte source-target relationship must be explicit instead of guessed from layer order.',
      ['matte', 'rectangle', 'ellipse', 'fill'],
      composition('Alpha Matte Rectangle', [
        shapeLayer(1, 'Matte Circle', [group('Matte Group', [ellipse('Matte Shape', [32, 32], [28, 28]), fill('Matte Fill', colors.ink)])], { trackMatteSource: 1 }),
        shapeLayer(2, 'Matted Box', [rectGroup(colors.amber, rect('Target Box', [32, 32], [44, 30]))], { trackMatteType: 1 })
      ])
    ),
    fixture(
      'precomp-static-child',
      'Root layer instantiates a precomposition containing a shape child.',
      'Precomp boundaries and child composition paths must be visible in source intent.',
      ['precomp', 'animated-position', 'rectangle', 'fill'],
      composition('Precomp Static Child', [
        precompLayer(1, 'Precomp Layer', 'box_precomp')
      ], [precompAsset])
    ),
    fixture(
      'time-remap-precomp-diagnosed',
      'Precomposition layer uses time remap to sample a child animation at a fixed local time.',
      'Time remap is a diagnosed semantic boundary until lowering consumes the evaluator exactly.',
      ['precomp', 'time-remap', 'diagnostic', 'animated-position'],
      composition('Time Remap Precomp Diagnosed', [
        precompLayer(1, 'Time Remapped Precomp', 'box_precomp', { timeRemap: fixed(0.5, 9) })
      ], [precompAsset]),
      { semanticStatus: 'diagnosed', expectedValidationEligible: false }
    )
  ];
}

function manifestEntry(entry) {
  const { document, ...rest } = entry;
  return rest;
}

function tableRow(entry) {
  return `| \`${entry.id}\` | ${entry.semanticStatus} | ${entry.coverage.map((item) => `\`${item}\``).join(', ')} | ${entry.bugClass} | ${entry.frames.map((frame) => frame.frame).join(', ')} |`;
}

function readme(entries) {
  return `# Lottie Oracle Fixture Corpus

This directory contains the curated source-intent oracle corpus for PureLottie.
Every fixture is intentionally small enough for review and has a committed
\`purelottie.lottie-web-intent\` snapshot produced by
\`Tools/LottieOracle/scripts/extract-intent.mjs\` with pinned
\`npm:lottie-web@5.13.0\`.

The large raw corpus under \`Tests/Fixtures/LottieCorpus\` is discovery material.
The files in this directory are the vetted regression set: each one isolates a
specific semantic bug class, selected source frames, and the numeric browser
trace used before any PNG comparison.

| Fixture | Status | Coverage | Bug class protected | Frames |
| --- | --- | --- | --- | --- |
${entries.map(tableRow).join('\n')}
`;
}

async function main() {
  const entries = fixtures();
  for (const entry of entries) {
    writeJson(path.join(fixturesRoot, `${entry.id}.json`), entry.document);
  }

  const manifest = entries.map(manifestEntry);
  writeJson(path.join(oracleRoot, 'oracle-fixtures.json'), manifest);
  fs.writeFileSync(path.join(fixturesRoot, 'README.md'), readme(manifest));

  if (!skipIntent) {
    const previousWorkingDirectory = process.cwd();
    process.chdir(oracleRoot);
    try {
      for (const entry of manifest) {
        const outputPath = path.join(intentRoot, `${entry.id}.json`);
        await extractLottieIntent({
          input: entry.lottie,
          output: outputPath,
          frames: entry.frames.map((frame) => Number(frame.frame)),
          scale: entry.scale,
          renderer: entry.renderer
        });
        process.stdout.write(`wrote ${path.relative(repoRoot, outputPath)}\n`);
      }
    } finally {
      process.chdir(previousWorkingDirectory);
    }
  }

  process.stdout.write(`${JSON.stringify({
    fixtureCount: manifest.length,
    manifest: path.relative(repoRoot, path.join(oracleRoot, 'oracle-fixtures.json')),
    fixtures: path.relative(repoRoot, fixturesRoot),
    traces: path.relative(repoRoot, intentRoot),
    intentGenerated: !skipIntent
  }, null, 2)}\n`);
}

await main();

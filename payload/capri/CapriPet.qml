import QtQuick

// Her body: one quad and the sprite shader (shaders/sprite.frag). js/capri.mjs poses it through
// draw() and places it through place(), on whole drawing frames only.
Item {
    id: pet
    property real scale: 0.6
    property real dpr: 1
    width: Math.round(352 * scale)
    height: Math.round(532 * scale)

    function draw(p) {
        body.uSeed = p.seed; body.uBoil = p.boil; body.uHair = p.hair; body.uHead = p.head; body.uMane = p.mane;
        body.uArmL = p.armL; body.uArmR = p.armR; body.uLongL = p.longL; body.uLongR = p.longR;
        body.uSit = p.sit; body.uKickL = p.kickL; body.uKickR = p.kickR;
        body.uSmear = Qt.point(p.smear[0], p.smear[1]); body.uEcho = Qt.point(p.echo[0], p.echo[1]);
        body.uGlitch = p.glitch; body.uGlitchSeed = p.glitchSeed; body.uSplit = p.split; body.uCollapse = p.collapse;
        body.uDissolve = p.dissolve; body.uSparkle = p.sparkle; body.uGrade = p.grade;
        body.uSil = Qt.vector4d(p.sil[0], p.sil[1], p.sil[2], p.silAmount);
        body.uMisreg = Qt.point(p.misreg[0], p.misreg[1]); body.uAlpha = p.alpha;
    }

    function place(t) {
        x = t.left;
        y = t.top;
        spin.origin.x = stretch.origin.x = t.origin.x;
        spin.origin.y = stretch.origin.y = t.origin.y;
        spin.angle = t.turn;
        stretch.xScale = t.sx;
        stretch.yScale = t.sy;
        squash.origin.x = t.squash ? t.squash.x : 0;
        squash.origin.y = t.squash ? t.squash.y : 0;
        squash.xScale = t.squash ? t.squash.sx : 1;
        squash.yScale = t.squash ? t.squash.sy : 1;
    }

    transform: Scale { id: squash }

    Image {
        id: texture
        source: "assets/capri-full.png"
        visible: false
        smooth: true
    }

    ShaderEffect {
        id: body
        anchors.fill: parent
        transform: [Scale { id: stretch }, Rotation { id: spin }]
        fragmentShader: "shaders/sprite.frag.qsb"
        property var uTex: texture
        property real uSeed: 0
        property real uBoil: 0.9
        property real uHair: 0
        property real uHead: 0
        property real uMane: 0
        property real uArmL: 0
        property real uArmR: 0
        property real uLongL: 1
        property real uLongR: 1
        property real uSit: 0
        property real uKickL: 0
        property real uKickR: 0
        property point uSmear: Qt.point(0, 0)
        property point uEcho: Qt.point(0, 0)
        property real uGlitch: 0
        property real uGlitchSeed: 0
        property real uSplit: 0
        property real uCollapse: 0
        property real uDissolve: 0
        property real uSparkle: 1
        property real uGrade: 1
        property vector4d uSil: Qt.vector4d(0.08, 0.06, 0.11, 0)
        property point uMisreg: Qt.point(-2.6, 2.2)
        property real uAlpha: 0
        // sprite pixels per device pixel: a mane speck stays about one screen pixel
        property real uPx: 1 / (pet.scale * pet.dpr)
    }
}

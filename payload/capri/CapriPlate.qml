import QtQuick
import "../"

Canvas {
    id: plate
    property color fillColor: ThemeBackend.base
    property bool jagged: false
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onFillColorChanged: requestPaint()
    onJaggedChanged: requestPaint()
    onPaint: {
        const c = getContext("2d"), w = width, h = height;
        c.reset();
        c.fillStyle = fillColor;
        c.beginPath();
        c.moveTo(0, Math.min(14, h / 3));
        c.lineTo(14, 0);
        if (jagged) {
            c.lineTo(w * .61, 0);
            c.lineTo(w * .63, 7);
            c.lineTo(w * .655, 0);
        }
        c.lineTo(w - 30, 0);
        c.lineTo(w, Math.min(30, h / 2));
        c.lineTo(w, h);
        c.lineTo(22, h);
        c.lineTo(0, h - Math.min(22, h / 3));
        c.closePath();
        c.fill();
    }
}

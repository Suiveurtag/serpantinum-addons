// Loads payload/calculator/AddonCalcEngine.js (a QML ".pragma library" script) into Node.
const fs = require('fs');
const path = require('path');
const vm = require('vm');

module.exports = function load() {
    const file = path.join(__dirname, '../../payload/calculator/AddonCalcEngine.js');
    const source = fs.readFileSync(file, 'utf8').replace(/^\.pragma library\s*$/m, '');
    const context = vm.createContext({ Math, Number, String, Error, parseInt, parseFloat, isFinite, isNaN, Infinity });
    vm.runInContext(source, context, { filename: file });
    return context;
};

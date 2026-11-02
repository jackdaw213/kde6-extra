/// module state: set by init() from main.qml
var _root = null;

/// called from main.qml Component.onCompleted.
function init(root) {
    _root = root;
}

/// for keyboard navigation
function moveFocusLeft() {
    _root.focusedIndex = _root.focusedIndex - 1;
    if (_root.focusedIndex < 0) _root.focusedIndex = _root.cycleKeyboard ? _root.clients.length - 1 : 0;
    scrollItemIntoView(_root.focusedIndex);
}

function moveFocusRight() {
    _root.focusedIndex = _root.focusedIndex + 1;
    const lastIndex = _root.clients.length - 1;
    if (_root.focusedIndex > lastIndex) _root.focusedIndex = _root.cycleKeyboard ? 0 : lastIndex;
    scrollItemIntoView(_root.focusedIndex);
}

function moveFocusUp(){
    if(_root.focusedIndex - _root.columnsCount >= 0) {
        _root.focusedIndex = _root.focusedIndex - _root.columnsCount;
        scrollItemIntoView(_root.focusedIndex);
    }
}

function moveFocusDown(){
    const clientsLen = _root.clients.length;
    if(_root.focusedIndex + _root.columnsCount < _root.clients.length) {
        _root.focusedIndex = _root.focusedIndex + _root.columnsCount;
        scrollItemIntoView(_root.focusedIndex);
    } else {
        _root.focusedIndex = _root.clients.length - 1;
        scrollItemIntoView(_root.focusedIndex);
    }
}

function scrollItemIntoView(index) {
    const item = _root.clientsRepeaterRef.itemAt(index);
    if (!item) return;
    const dy = item.y, viewHeight = _root.height * 0.95;
    const scrollStep = (_root.cardHeight + _root.gridSpacing)  / _root.scrollViewRef.contentHeight;
    if (dy > viewHeight) _root.scrollViewRef.ScrollBar.vertical.position += scrollStep;
    else if (dy < _root.scrollViewRef.ScrollBar.vertical.position) _root.scrollViewRef.ScrollBar.vertical.position -= scrollStep;
}

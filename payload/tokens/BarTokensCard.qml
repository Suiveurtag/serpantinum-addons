import QtQuick
import QtQuick.Layouts
import "../"
import "../reusables"
import "../reusables/guide"
import "../guide/bar/modules"

// Settings → Bar → Modules → AI Tokens: live preview and the providers shown when the bar module is hovered.
// Injected into the modules page by install.py (patch_bar_modules_tab); absent when the tokens addon is removed.
BarModuleCard {
    id: card
    title: qsTr("AI Tokens")
    moduleId: "tokens"
    showPreview: true
    previewSideHeight: 120

    // The preview shows the split even without hovering.
    widgetComponent: Component {
        BarPreviewWidget { property bool forceSplit: true }
    }

    readonly property var hoverIds: {
        let bs = Config.getSetting("bar", {});
        return bs && Array.isArray(bs.tokensHoverProviders) ? bs.tokensHoverProviders : Tokens.defaultHoverProviders;
    }

    function setHoverProviders(ids) {
        // Stored in catalog order, so the bar shows providers in the same order whatever the click order was.
        let current = Config.getSetting("bar", {});
        current.tokensHoverProviders = Tokens.providerCatalog.map(p => p.id).filter(id => ids.indexOf(id) !== -1);
        Config.setSetting("bar", current);
    }

    function toggleProvider(id, on) {
        let ids = card.hoverIds.filter(x => x !== id);
        if (on) ids.push(id);
        setHoverProviders(ids);
    }

    Repeater {
        model: Tokens.providerCatalog
        delegate: SettingsRow {
            required property var modelData
            rootObj: card.rootObj
            settingId: "bar_tokens_hover_" + modelData.id
            searchKeywords: "ai tokens hover tooltip survol " + modelData.name.toLowerCase()
            baseColor: Qt.alpha(ThemeBackend.surface1, 0.35)
            // Platform logo, tinted with a fixed colour (IconButton uses iconTextColor for the image).
            icon: Qt.resolvedUrl(modelData.logo).toString()
            iconTextColor: "#7E7065"
            title: modelData.name
            description: qsTr("Show this provider when the bar module is hovered")

            Toggle {
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                checked: card.hoverIds.indexOf(modelData.id) !== -1
                // Keep at least one provider on hover.
                enabled: !checked || card.hoverIds.length > 1
                accentColor: ThemeBackend.mauve
                baseColor: ThemeBackend.surface1
                handleColor: ThemeBackend.crust
                handleOffColor: ThemeBackend.text
                onToggled: function(c) {
                    card.toggleProvider(modelData.id, c);
                }
            }
        }
    }
}

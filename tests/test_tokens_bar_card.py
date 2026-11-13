"""The AI Tokens card in Settings → Bar → Modules is injected once, and removed cleanly with the addon."""
import unittest

from test_changes import ROOT, load

SAMPLE = '''        ColumnLayout {
            BarMediaCard { tab: barModulesRoot }
        }
'''


class TokensBarCard(unittest.TestCase):
    def setUp(self):
        self.tokens = load('tokens_bar_card', ROOT/'tokens.py')

    def test_card_is_inserted_once_after_media(self):
        once = self.tokens.patch_modules_tab(SAMPLE)
        self.assertEqual(once.count('BarTokensCard { tab: barModulesRoot }'), 1)
        self.assertEqual(self.tokens.patch_modules_tab(once), once)

    def test_remove_restores_the_upstream_text(self):
        self.assertEqual(self.tokens.remove(self.tokens.patch_modules_tab(SAMPLE)), SAMPLE)

    def test_new_layout_inserts_card_in_settings(self):
        source = '                sourceComponent: BarMediaCard { tab: barModulesRoot }\n            }\n'
        result = self.tokens.patch_modules_settings(source)
        self.assertEqual(result.count('BarTokensCard { tab: barModulesRoot }'), 1)
        self.assertEqual(self.tokens.patch_modules_settings(result), result)
        self.assertEqual(self.tokens.remove(result), source)

    def test_qmldir_declares_the_card(self):
        self.assertIn('BarTokensCard 1.0 tokens/BarTokensCard.qml', self.tokens.TYPES)


if __name__ == '__main__':
    unittest.main()

"""Mouse editing and pasted search drafts keep the native field usable."""
import pytest
from playwright.sync_api import expect
from tests.ui.test_agent_conversation import ui_agent
from tests.ui.test_goal_window import _discuss
from tests.ui.views import FIELD


def test_click_inside_a_draft_keeps_the_clicked_caret(ui_agent):
    page = ui_agent.page
    _discuss(page)
    page.keyboard.press('Control+k')
    field = page.locator(FIELD)
    field.fill('Alpha beta gamma')
    field.click(position={'x': 4, 'y': 15})
    assert field.evaluate('e => e.selectionStart') < 5
    field.press('X')
    assert field.input_value().startswith('X')


def test_double_click_keeps_the_native_selection(ui_agent):
    page = ui_agent.page
    _discuss(page)
    page.keyboard.press('Control+k')
    field = page.locator(FIELD)
    field.fill('Alpha beta gamma')
    field.dblclick(position={'x': 20, 'y': 15})
    assert field.evaluate('e => e.value.slice(e.selectionStart,e.selectionEnd)') == 'Alpha'
    field.press('X')
    expect(field).to_have_value('X beta gamma')

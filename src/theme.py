"""电脑版亮暗主题：跟随系统 + 手动切换 + 亮色背景由原背景照片换算得到。

主题令牌集中在这里，qtui.py 与 src/info_dialog.py 共用：
- `build_theme(mode)` 返回一份颜色令牌字典（CSS 字符串，可直接进 QSS）
- `main_stylesheet(theme)` 生成主窗口样式表
- `draw_dark_background()` / `draw_light_background()` 生成窗口背景
- 亮色背景不额外引入图片资源：把原背景照片灰度化、反相后套纸白→墨绿调色板，
  夜拍素材就变成大面积纸白加墨绿层次，`LightBackgroundBrush` 负责换算与缓存
"""

import json
import os
import re
import sys

from PySide6.QtCore import QPointF, QRect, Qt
from PySide6.QtGui import (
    QColor, QImage, QLinearGradient, QPainter, QPalette, QRadialGradient, QPixmap, qRgba,
)

from utils.auxiliary_util import get_base_path

MODE_FOLLOW = "follow"
MODE_LIGHT = "light"
MODE_DARK = "dark"
# 可持久化的三种状态；follow 只在“用户还没手动选过”时作为默认值存在，界面上没有对应按钮
MODES = (MODE_FOLLOW, MODE_LIGHT, MODE_DARK)
# 标题栏分段控件只暴露亮 / 暗两档，默认高亮的是 follow 解析出来的那一档
SWITCH_MODES = (MODE_LIGHT, MODE_DARK)
MODE_SHORT_LABELS = {MODE_LIGHT: "亮", MODE_DARK: "暗"}
MODE_TOOLTIPS = {
    MODE_LIGHT: "固定使用亮色主题",
    MODE_DARK: "固定使用暗色主题",
}

SETTINGS_FILE_NAME = "ui_settings.json"

# 界面字体族：macOS 上没有微软雅黑，优先用系统中文字体，避免 Qt 反复做字体回退
if sys.platform == "darwin":
    UI_FONT_FAMILIES_LIST = ["PingFang SC", "Hiragino Sans GB", "Heiti SC",
                             "Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI"]
else:
    UI_FONT_FAMILIES_LIST = ["Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI",
                             "PingFang SC"]

UI_FONT_FAMILIES = ", ".join(f'"{name}"' for name in UI_FONT_FAMILIES_LIST) + ", sans-serif"

DARK_THEME = {
    "mode": MODE_DARK,
    # 窗口与文字
    "window_solid": "rgb(7, 16, 19)",
    "dialog_bg": "rgb(9, 20, 26)",
    "text": "rgb(238, 246, 242)",
    "text_muted": "rgba(229, 246, 240, 210)",
    "title_text": "rgb(255, 255, 252)",
    # 面板
    "header_bg": "rgba(8, 14, 24, 156)",
    "header_border": "rgba(255, 255, 255, 76)",
    "panel_bg": "rgba(6, 14, 22, 166)",
    "panel_border": "rgba(78, 255, 216, 72)",
    "panel_title_bg": "rgba(11, 28, 34, 210)",
    "panel_title_border": "rgba(88, 255, 220, 124)",
    "panel_title_text": "rgb(232, 255, 248)",
    "hint_bg": "rgba(8, 14, 24, 118)",
    "hint_border": "rgba(72, 255, 215, 82)",
    "hint_text": "rgba(255, 255, 252, 224)",
    "warn_bg": "rgba(34, 22, 8, 182)",
    "warn_border": "rgba(255, 204, 95, 154)",
    "warn_text": "rgb(255, 241, 205)",
    # 输入控件
    "input_bg": "rgba(6, 18, 27, 188)",
    "input_border": "rgba(94, 255, 223, 104)",
    "input_hover_bg": "rgba(7, 25, 35, 206)",
    "input_focus_bg": "rgba(7, 31, 43, 226)",
    "input_focus_border": "rgba(75, 255, 218, 230)",
    "input_text": "rgb(239, 255, 250)",
    "input_placeholder": "rgba(226, 244, 238, 154)",
    "input_selection_bg": "rgb(75, 255, 218)",
    "input_selection_text": "rgb(4, 20, 23)",
    "combo_dropdown_border": "rgba(94, 255, 223, 96)",
    "combo_popup_bg": "rgb(8, 20, 28)",
    "combo_popup_text": "rgb(239, 255, 250)",
    "combo_item_hover_bg": "rgb(15, 68, 67)",
    "combo_item_hover_text": "rgb(255, 255, 255)",
    "combo_item_selected_bg": "rgb(17, 122, 109)",
    "combo_item_selected_text": "rgb(255, 255, 255)",
    # 按钮
    "button_bg": "rgba(8, 18, 26, 170)",
    "button_border": "rgba(91, 255, 222, 78)",
    "button_text": "rgb(240, 255, 250)",
    "button_hover_bg": "rgba(13, 35, 43, 214)",
    "button_hover_border": "rgba(75, 255, 218, 212)",
    "button_hover_text": "rgb(255, 255, 255)",
    "button_pressed_bg": "rgba(7, 45, 52, 232)",
    "button_pressed_border": "rgba(169, 255, 232, 236)",
    "button_disabled_bg": "rgba(26, 35, 39, 126)",
    "button_disabled_text": "rgba(210, 225, 219, 138)",
    "button_disabled_border": "rgba(210, 225, 219, 54)",
    "accent": "rgb(75, 255, 218)",
    "accent_deep": "rgb(16, 128, 111)",
    "accent_text": "rgb(255, 255, 255)",
    "start_bg": "rgba(11, 116, 104, 226)",
    "start_border": "rgba(69, 255, 214, 174)",
    "start_hover_bg": "rgba(15, 158, 136, 236)",
    "start_hover_border": "rgba(82, 255, 218, 240)",
    "start_pressed_bg": "rgb(8, 95, 88)",
    "stop_bg": "rgba(159, 42, 67, 225)",
    "stop_border": "rgba(255, 82, 153, 174)",
    "stop_hover_bg": "rgba(196, 49, 92, 236)",
    "stop_hover_border": "rgba(255, 91, 166, 236)",
    "stop_pressed_bg": "rgb(124, 26, 57)",
    "shuiyuan_bg": "rgba(6, 18, 27, 182)",
    "shuiyuan_border": "rgba(85, 255, 221, 104)",
    "shuiyuan_hover_bg": "rgba(8, 31, 43, 218)",
    "shuiyuan_hover_border": "rgba(85, 255, 221, 216)",
    "shuiyuan_pressed_bg": "rgba(7, 45, 52, 232)",
    "shuiyuan_pressed_border": "rgba(169, 255, 232, 236)",
    "github_bg": "rgba(8, 14, 24, 184)",
    "github_border": "rgba(129, 206, 255, 116)",
    "github_text": "rgb(255, 255, 255)",
    "github_hover_bg": "rgba(11, 29, 45, 222)",
    "github_hover_border": "rgba(118, 205, 255, 220)",
    "github_pressed_bg": "rgb(16, 25, 30)",
    "gold_bg": "rgba(32, 25, 9, 156)",
    "gold_border": "rgba(255, 226, 105, 118)",
    "gold_text": "rgb(255, 246, 202)",
    "gold_hover_bg": "rgba(68, 50, 10, 204)",
    "gold_hover_border": "rgba(255, 228, 96, 236)",
    "gold_pressed_bg": "rgba(98, 72, 12, 224)",
    "gold_disabled_bg": "rgba(30, 34, 32, 126)",
    "gold_disabled_border": "rgba(255, 226, 105, 54)",
    "gold_disabled_text": "rgba(255, 246, 202, 124)",
    "delete_bg": "rgba(120, 26, 52, 200)",
    "delete_border": "rgba(255, 82, 153, 150)",
    "delete_text": "rgb(255, 232, 238)",
    "delete_hover_bg": "rgba(159, 42, 67, 225)",
    "delete_hover_border": "rgba(255, 91, 166, 220)",
    # 主题切换分段控件
    "switch_bg": "rgba(8, 14, 24, 150)",
    "switch_border": "rgba(255, 255, 255, 66)",
    "switch_text": "rgba(232, 244, 240, 210)",
    "switch_hover_bg": "rgba(255, 255, 252, 34)",
    "switch_checked_bg": "rgba(16, 128, 111, 235)",
    "switch_checked_text": "rgb(255, 255, 255)",
    # 进度 / 日志 / 勾选
    "progress_bg": "rgba(5, 15, 23, 186)",
    "progress_border": "rgba(84, 255, 222, 104)",
    "progress_text": "rgb(226, 255, 248)",
    "progress_chunk_start": "rgba(58, 255, 214, 230)",
    "progress_chunk_end": "rgba(122, 206, 255, 224)",
    "log_bg": "rgba(3, 12, 20, 188)",
    "log_border": "rgba(84, 255, 222, 112)",
    "log_text": "rgb(168, 247, 255)",
    "log_selection_bg": "rgb(75, 255, 218)",
    "log_selection_text": "rgb(4, 20, 23)",
    "checkbox_bg": "rgba(255, 255, 252, 226)",
    "checkbox_border": "rgba(139, 164, 153, 178)",
    "checkbox_checked_bg": "rgb(16, 128, 111)",
    "checkbox_disabled_bg": "rgba(225, 231, 225, 178)",
    "checkbox_disabled_border": "rgba(220, 227, 217, 142)",
    # 滚动条 / 提示 / 链接
    "scroll_bg": "rgba(8, 14, 24, 82)",
    "scroll_handle": "rgba(255, 255, 252, 118)",
    "scroll_handle_hover": "rgba(255, 255, 252, 178)",
    "tooltip_bg": "rgb(27, 38, 44)",
    "tooltip_border": "rgb(91, 122, 111)",
    "tooltip_text": "rgb(255, 255, 252)",
    "link": "rgb(121, 255, 225)",
    "link_hover": "rgb(180, 255, 238)",
    # 背景绘制（暗色沿用背景照片 + 渐变遮罩）
    "photo_overlay_top": "rgba(3, 12, 20, 209)",
    "photo_overlay_bottom": "rgba(3, 12, 20, 224)",
    "paper_top": "rgb(7, 16, 19)",
    "paper_bottom": "rgb(7, 16, 19)",
    "photo_ink": "rgb(7, 16, 19)",
    "bg_wash_inner": "rgba(7, 16, 19, 0)",
    "bg_wash_outer": "rgba(7, 16, 19, 0)",
    # 路线轮廓小图
    "route_line": "rgba(75, 255, 218, 220)",
    "route_start": "rgb(22, 163, 74)",
    "route_end": "rgb(220, 38, 38)",
    "route_placeholder": "rgb(140, 160, 170)",
    # 日志级别配色
    "log_info": "#A8F7FF",
    "log_warning": "#FFE66D",
    "log_error": "#FF5C9F",
    "log_success": "#55FFD8",
    # 按钮辉光
    "glow_accent": "rgba(69, 255, 214, 180)",
    "glow_danger": "rgba(255, 82, 153, 190)",
    "glow_warn": "rgba(255, 226, 105, 180)",
    "glow_info": "rgba(118, 205, 255, 185)",
    # 关于窗口
    "help_panel_bg": "rgba(8, 14, 24, 148)",
    "help_panel_border": "rgba(255, 255, 255, 66)",
    "help_title_text": "rgb(255, 255, 252)",
    "help_body_text": "rgba(255, 255, 255, 230)",
    "help_pill_bg": "rgba(255, 255, 255, 36)",
    "help_pill_border": "rgba(255, 255, 255, 66)",
    "help_pill_text": "rgba(255, 255, 255, 235)",
    "help_button_bg": "rgba(255, 255, 255, 31)",
    "help_button_border": "rgba(255, 255, 255, 87)",
    "help_button_text": "rgb(255, 255, 252)",
    "help_button_hover_bg": "rgba(255, 255, 255, 56)",
    "help_button_hover_border": "rgba(255, 255, 255, 133)",
    "help_button_disabled_text": "rgba(255, 255, 255, 133)",
    "status_update": "#7cffb2",
    "status_ok": "rgba(255, 255, 255, 184)",
    "status_error": "#ff9c9c",
}

LIGHT_THEME = {
    "mode": MODE_LIGHT,
    # 窗口与文字
    "window_solid": "rgb(246, 249, 247)",
    "dialog_bg": "rgb(248, 250, 249)",
    "text": "rgb(26, 42, 46)",
    "text_muted": "rgba(58, 82, 86, 205)",
    "title_text": "rgb(16, 34, 38)",
    # 面板
    "header_bg": "rgba(255, 255, 255, 214)",
    "header_border": "rgba(20, 84, 74, 72)",
    "panel_bg": "rgba(255, 255, 255, 226)",
    "panel_border": "rgba(20, 84, 74, 74)",
    "panel_title_bg": "rgba(232, 242, 238, 242)",
    "panel_title_border": "rgba(20, 84, 74, 118)",
    "panel_title_text": "rgb(18, 62, 54)",
    "hint_bg": "rgba(255, 255, 255, 208)",
    "hint_border": "rgba(18, 110, 96, 120)",
    "hint_text": "rgb(44, 68, 72)",
    "warn_bg": "rgba(255, 247, 237, 240)",
    "warn_border": "rgba(214, 150, 60, 200)",
    "warn_text": "rgb(120, 45, 18)",
    # 输入控件
    "input_bg": "rgba(255, 255, 255, 242)",
    "input_border": "rgba(30, 90, 80, 124)",
    "input_hover_bg": "rgba(246, 251, 249, 250)",
    "input_focus_bg": "rgb(255, 255, 255)",
    "input_focus_border": "rgba(18, 110, 96, 225)",
    "input_text": "rgb(24, 40, 44)",
    "input_placeholder": "rgba(70, 96, 100, 160)",
    "input_selection_bg": "rgb(18, 110, 96)",
    "input_selection_text": "rgb(255, 255, 255)",
    "combo_dropdown_border": "rgba(30, 90, 80, 110)",
    "combo_popup_bg": "rgb(255, 255, 255)",
    "combo_popup_text": "rgb(26, 42, 46)",
    "combo_item_hover_bg": "rgba(18, 110, 96, 34)",
    "combo_item_hover_text": "rgb(16, 40, 44)",
    "combo_item_selected_bg": "rgb(18, 110, 96)",
    "combo_item_selected_text": "rgb(255, 255, 255)",
    # 按钮
    "button_bg": "rgba(255, 255, 255, 234)",
    "button_border": "rgba(30, 90, 80, 124)",
    "button_text": "rgb(26, 46, 50)",
    "button_hover_bg": "rgb(240, 247, 244)",
    "button_hover_border": "rgba(18, 110, 96, 200)",
    "button_hover_text": "rgb(14, 34, 38)",
    "button_pressed_bg": "rgb(224, 235, 231)",
    "button_pressed_border": "rgba(13, 84, 72, 220)",
    "button_disabled_bg": "rgba(236, 240, 238, 210)",
    "button_disabled_text": "rgba(120, 140, 136, 150)",
    "button_disabled_border": "rgba(120, 140, 136, 90)",
    "accent": "rgb(18, 110, 96)",
    "accent_deep": "rgb(13, 84, 72)",
    "accent_text": "rgb(255, 255, 255)",
    "start_bg": "rgb(18, 110, 96)",
    "start_border": "rgb(18, 110, 96)",
    "start_hover_bg": "rgb(15, 130, 112)",
    "start_hover_border": "rgb(15, 130, 112)",
    "start_pressed_bg": "rgb(11, 84, 72)",
    "stop_bg": "rgb(176, 44, 68)",
    "stop_border": "rgb(176, 44, 68)",
    "stop_hover_bg": "rgb(196, 55, 80)",
    "stop_hover_border": "rgb(196, 55, 80)",
    "stop_pressed_bg": "rgb(146, 32, 54)",
    "shuiyuan_bg": "rgba(255, 255, 255, 236)",
    "shuiyuan_border": "rgba(18, 110, 96, 150)",
    "shuiyuan_hover_bg": "rgb(238, 247, 244)",
    "shuiyuan_hover_border": "rgba(18, 110, 96, 215)",
    "shuiyuan_pressed_bg": "rgb(224, 236, 232)",
    "shuiyuan_pressed_border": "rgba(13, 84, 72, 220)",
    "github_bg": "rgba(244, 248, 252, 238)",
    "github_border": "rgba(40, 90, 140, 140)",
    "github_text": "rgb(20, 45, 70)",
    "github_hover_bg": "rgb(232, 240, 250)",
    "github_hover_border": "rgba(40, 90, 140, 210)",
    "github_pressed_bg": "rgb(218, 229, 241)",
    "gold_bg": "rgba(255, 249, 235, 238)",
    "gold_border": "rgba(176, 120, 20, 145)",
    "gold_text": "rgb(96, 60, 10)",
    "gold_hover_bg": "rgb(255, 242, 219)",
    "gold_hover_border": "rgba(176, 120, 20, 215)",
    "gold_pressed_bg": "rgb(248, 229, 196)",
    "gold_disabled_bg": "rgba(240, 240, 236, 220)",
    "gold_disabled_border": "rgba(176, 120, 20, 70)",
    "gold_disabled_text": "rgba(120, 100, 70, 140)",
    "delete_bg": "rgba(255, 240, 243, 238)",
    "delete_border": "rgba(176, 44, 68, 150)",
    "delete_text": "rgb(140, 28, 52)",
    "delete_hover_bg": "rgb(255, 228, 234)",
    "delete_hover_border": "rgba(176, 44, 68, 215)",
    # 主题切换分段控件
    "switch_bg": "rgba(255, 255, 255, 224)",
    "switch_border": "rgba(20, 84, 74, 90)",
    "switch_text": "rgb(52, 74, 78)",
    "switch_hover_bg": "rgba(20, 84, 74, 28)",
    "switch_checked_bg": "rgb(18, 110, 96)",
    "switch_checked_text": "rgb(255, 255, 255)",
    # 进度 / 日志 / 勾选
    "progress_bg": "rgba(20, 84, 74, 36)",
    "progress_border": "rgba(30, 90, 80, 110)",
    "progress_text": "rgb(24, 52, 56)",
    "progress_chunk_start": "rgba(18, 110, 96, 235)",
    "progress_chunk_end": "rgba(72, 152, 190, 235)",
    "log_bg": "rgba(251, 253, 252, 242)",
    "log_border": "rgba(30, 90, 80, 120)",
    "log_text": "rgb(28, 60, 70)",
    "log_selection_bg": "rgb(18, 110, 96)",
    "log_selection_text": "rgb(255, 255, 255)",
    "checkbox_bg": "rgb(255, 255, 255)",
    "checkbox_border": "rgba(30, 90, 80, 165)",
    "checkbox_checked_bg": "rgb(18, 110, 96)",
    "checkbox_disabled_bg": "rgba(232, 236, 234, 220)",
    "checkbox_disabled_border": "rgba(120, 140, 136, 150)",
    # 滚动条 / 提示 / 链接
    "scroll_bg": "rgba(20, 84, 74, 28)",
    "scroll_handle": "rgba(20, 84, 74, 110)",
    "scroll_handle_hover": "rgba(20, 84, 74, 165)",
    "tooltip_bg": "rgb(250, 252, 251)",
    "tooltip_border": "rgba(20, 84, 74, 140)",
    "tooltip_text": "rgb(26, 42, 46)",
    "link": "rgb(18, 110, 96)",
    "link_hover": "rgb(13, 84, 72)",
    # 背景绘制（亮色：纸白渐变 + 庙门线描）
    "photo_overlay_top": "rgba(255, 255, 255, 0)",
    "photo_overlay_bottom": "rgba(255, 255, 255, 0)",
    "paper_top": "rgb(252, 253, 252)",
    "paper_bottom": "rgb(232, 239, 236)",
    "photo_ink": "rgb(18, 110, 96)",
    "bg_wash_inner": "rgba(255, 255, 255, 150)",
    "bg_wash_outer": "rgba(255, 255, 255, 0)",
    # 路线轮廓小图
    "route_line": "rgba(18, 110, 96, 230)",
    "route_start": "rgb(20, 120, 60)",
    "route_end": "rgb(190, 40, 60)",
    "route_placeholder": "rgb(140, 158, 164)",
    # 日志级别配色
    "log_info": "#1f5f74",
    "log_warning": "#8a6100",
    "log_error": "#b3264c",
    "log_success": "#0f7a63",
    # 按钮辉光
    "glow_accent": "rgba(18, 110, 96, 130)",
    "glow_danger": "rgba(176, 44, 68, 130)",
    "glow_warn": "rgba(176, 120, 20, 130)",
    "glow_info": "rgba(40, 90, 140, 130)",
    # 关于窗口
    "help_panel_bg": "rgba(255, 255, 255, 214)",
    "help_panel_border": "rgba(20, 84, 74, 80)",
    "help_title_text": "rgb(16, 34, 38)",
    "help_body_text": "rgb(44, 66, 70)",
    "help_pill_bg": "rgba(18, 110, 96, 26)",
    "help_pill_border": "rgba(18, 110, 96, 90)",
    "help_pill_text": "rgb(20, 60, 54)",
    "help_button_bg": "rgba(255, 255, 255, 232)",
    "help_button_border": "rgba(20, 84, 74, 110)",
    "help_button_text": "rgb(26, 46, 50)",
    "help_button_hover_bg": "rgb(238, 246, 243)",
    "help_button_hover_border": "rgba(18, 110, 96, 180)",
    "help_button_disabled_text": "rgba(90, 110, 106, 150)",
    "status_update": "#0f7a63",
    "status_ok": "rgba(58, 82, 86, 210)",
    "status_error": "#b3264c",
}

THEMES = {MODE_LIGHT: LIGHT_THEME, MODE_DARK: DARK_THEME}


def build_theme(mode):
    """按模式（follow/light/dark）返回一份颜色令牌字典。"""
    return dict(THEMES[resolve_mode(mode)])


def resolve_mode(mode):
    """把 follow 解析成实际的 light / dark。"""
    if mode == MODE_LIGHT:
        return MODE_LIGHT
    if mode == MODE_DARK:
        return MODE_DARK
    return system_mode()


def system_mode():
    """读取系统亮暗设置；读不到就退回暗色（沿用历史外观）。"""
    try:
        app = _application_instance()
        if app is not None:
            scheme = app.styleHints().colorScheme()
            if scheme == Qt.ColorScheme.Dark:
                return MODE_DARK
            if scheme == Qt.ColorScheme.Light:
                return MODE_LIGHT
    except Exception:
        pass

    if sys.platform == "win32":
        fallback = _system_mode_windows()
    elif sys.platform == "darwin":
        fallback = _system_mode_macos()
    else:
        fallback = _system_mode_linux()
    return fallback or MODE_DARK


def _application_instance():
    try:
        from PySide6.QtWidgets import QApplication
        return QApplication.instance()
    except Exception:
        return None


def _system_mode_windows():
    try:
        import winreg

        key = winreg.OpenKey(
            winreg.HKEY_CURRENT_USER,
            r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
        )
        value, _ = winreg.QueryValueEx(key, "AppsUseLightTheme")
        winreg.CloseKey(key)
        return MODE_LIGHT if int(value) else MODE_DARK
    except Exception:
        return None


def _system_mode_macos():
    try:
        import subprocess

        result = subprocess.run(
            ["defaults", "read", "-g", "AppleInterfaceMode"],
            capture_output=True, text=True, timeout=2,
        )
        if result.returncode == 0:
            return MODE_DARK if result.stdout.strip().lower() == "dark" else MODE_LIGHT
    except Exception:
        return None
    return None


def _system_mode_linux():
    gtk_theme = os.environ.get("GTK_THEME", "")
    if gtk_theme and "dark" in gtk_theme.lower():
        return MODE_DARK
    try:
        import subprocess

        result = subprocess.run(
            ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"],
            capture_output=True, text=True, timeout=2,
        )
        if "prefer-dark" in result.stdout:
            return MODE_DARK
        if "prefer-light" in result.stdout:
            return MODE_LIGHT
    except Exception:
        return None
    return None


def settings_path():
    return os.path.join(get_base_path(), SETTINGS_FILE_NAME)


def load_ui_settings():
    try:
        with open(settings_path(), "r", encoding="utf-8") as settings_file:
            data = json.load(settings_file)
        if isinstance(data, dict):
            return data
    except Exception:
        pass
    return {}


def save_ui_settings(data):
    try:
        with open(settings_path(), "w", encoding="utf-8") as settings_file:
            json.dump(data, settings_file, ensure_ascii=False, indent=2)
    except Exception:
        pass


def load_theme_mode():
    mode = load_ui_settings().get("theme_mode")
    return mode if mode in MODES else MODE_FOLLOW


def save_theme_mode(mode):
    data = load_ui_settings()
    data["theme_mode"] = mode
    save_ui_settings(data)


def apply_palette(target, theme):
    """把主题写进 QPalette，没写 QSS 的原生部分（对话框、菜单）也跟着走。"""
    palette = target.palette()
    window = qcolor(theme["window_solid"])
    text = qcolor(theme["text"])
    muted = qcolor(theme["text_muted"])
    accent = qcolor(theme["accent"])

    palette.setColor(QPalette.Window, window)
    palette.setColor(QPalette.WindowText, text)
    palette.setColor(QPalette.Base, qcolor(theme["input_bg"]))
    palette.setColor(QPalette.AlternateBase, qcolor(theme["log_bg"]))
    palette.setColor(QPalette.ToolTipBase, qcolor(theme["tooltip_bg"]))
    palette.setColor(QPalette.ToolTipText, qcolor(theme["tooltip_text"]))
    palette.setColor(QPalette.Text, text)
    palette.setColor(QPalette.Button, qcolor(theme["button_bg"]))
    palette.setColor(QPalette.ButtonText, qcolor(theme["button_text"]))
    palette.setColor(QPalette.BrightText, QColor("red"))
    palette.setColor(QPalette.Link, accent)
    palette.setColor(QPalette.Highlight, accent)
    palette.setColor(QPalette.HighlightedText, qcolor(theme["accent_text"]))
    palette.setColor(QPalette.PlaceholderText, qcolor(theme["input_placeholder"]))

    palette.setColor(QPalette.ColorGroup.Active, QPalette.ColorRole.WindowText, text)
    palette.setColor(QPalette.ColorGroup.Active, QPalette.ColorRole.Text, text)
    palette.setColor(QPalette.ColorGroup.Active, QPalette.ColorRole.ButtonText, qcolor(theme["button_text"]))
    palette.setColor(QPalette.ColorGroup.Inactive, QPalette.ColorRole.WindowText, text)
    palette.setColor(QPalette.ColorGroup.Inactive, QPalette.ColorRole.Text, text)
    palette.setColor(QPalette.ColorGroup.Inactive, QPalette.ColorRole.ButtonText, qcolor(theme["button_text"]))
    palette.setColor(QPalette.ColorGroup.Disabled, QPalette.ColorRole.WindowText, muted)
    palette.setColor(QPalette.ColorGroup.Disabled, QPalette.ColorRole.Text, muted)
    palette.setColor(QPalette.ColorGroup.Disabled, QPalette.ColorRole.ButtonText, muted)
    palette.setColor(QPalette.ColorGroup.Disabled, QPalette.ColorRole.Window, window)

    target.setPalette(palette)
    return palette


def log_color(theme, level):
    key = {"error": "log_error", "warning": "log_warning", "success": "log_success"}.get(level, "log_info")
    return qcolor(theme[key])


def glow_color(theme, kind):
    return qcolor(theme.get("glow_" + kind, theme["glow_accent"]))


def qcolor(value):
    """把令牌里的 rgb()/rgba() 字符串转成 QColor（QColor 只认 #RRGGBB 和命名色）。"""
    if isinstance(value, QColor):
        return QColor(value)
    match = re.match(r"rgba?\(([^)]*)\)", str(value).strip())
    if match:
        parts = [part.strip() for part in match.group(1).split(",")]
        try:
            numbers = [max(0, min(255, int(float(part)))) for part in parts]
        except ValueError:
            numbers = []
        if len(numbers) >= 4:
            return QColor(*numbers[:4])
        if len(numbers) == 3:
            return QColor(*numbers)
    return QColor(value)


def _fill_tokens(stylesheet, theme):
    """用令牌替换 QSS 里的 __token__ 占位符（QSS 本身满是花括号，不能用 str.format）。"""
    for key, value in theme.items():
        if isinstance(value, str):
            stylesheet = stylesheet.replace("__" + key + "__", value)
    return stylesheet.replace("__UI_FONT__", UI_FONT_FAMILIES)


_MAIN_QSS = """
            /* 基础设置 */
            QWidget {
                background-color: transparent;
                color: __text__;
                font-family: __UI_FONT__;
            }

            #mainWindow, #contentShell, #mainScrollArea, #scrollContent {
                background-color: transparent;
            }

            /* 子对话框（二次验证、消息框、承诺书）跟随主题 */
            QDialog {
                background-color: __dialog_bg__;
            }

            #appHeader {
                background-color: __header_bg__;
                border: 1px solid __header_border__;
                border-radius: 8px;
            }

            #appTitle {
                color: __title_text__;
                font-size: 20pt;
                font-weight: 800;
                background-color: transparent;
            }

            #sectionHint {
                color: __text_muted__;
                font-size: 9pt;
                background-color: transparent;
            }

            #floatingHint {
                color: __hint_text__;
                font-size: 9pt;
                background-color: __hint_bg__;
                border: 1px solid __hint_border__;
                border-radius: 7px;
                padding: 6px 8px;
            }

            #warningBox {
                background-color: __warn_bg__;
                color: __warn_text__;
                border: 1px solid __warn_border__;
                border-radius: 8px;
                padding: 14px;
                font-size: 11pt;
                font-weight: 600;
                line-height: 145%;
            }

            /* GroupBox 样式 */
            QGroupBox {
                font-size: 12pt;
                font-weight: bold;
                margin-top: 0;
                border: 1px solid __panel_border__;
                border-radius: 8px;
                padding: 36px 12px 12px 12px;
                color: __panel_title_text__;
                background-color: __panel_bg__;
            }
            QGroupBox::title {
                subcontrol-origin: padding;
                subcontrol-position: top left;
                left: 12px;
                top: 8px;
                padding: 4px 12px;
                color: __panel_title_text__;
                background-color: __panel_title_bg__;
                border: 1px solid __panel_title_border__;
                border-radius: 10px;
            }

            /* 确保所有标签和输入框可见 */
            QLabel {
                color: __text__;
                background-color: transparent;
                font-size: 11pt;
            }

            QLineEdit, QComboBox, QDateTimeEdit {
                background-color: __input_bg__;
                border: 1px solid __input_border__;
                border-radius: 6px;
                padding: 9px;
                color: __input_text__;
                font-size: 11pt;
                min-height: 22px;
                selection-background-color: __input_selection_bg__;
                selection-color: __input_selection_text__;
                placeholder-text-color: __input_placeholder__;
            }

            QLineEdit:hover, QComboBox:hover, QDateTimeEdit:hover {
                border: 1px solid __input_focus_border__;
                background-color: __input_hover_bg__;
            }

            QLineEdit:focus, QComboBox:focus, QDateTimeEdit:focus {
                border: 1px solid __input_focus_border__;
                background-color: __input_focus_bg__;
            }

            QComboBox::drop-down {
                subcontrol-origin: padding;
                subcontrol-position: top right;
                width: 20px;
                border-left-width: 1px;
                border-left-color: __combo_dropdown_border__;
                border-left-style: solid;
                border-top-right-radius: 6px;
                border-bottom-right-radius: 6px;
            }
            QComboBox QAbstractItemView {
                background-color: __combo_popup_bg__;
                color: __combo_popup_text__;
                border: 1px solid __input_border__;
                border-radius: 6px;
                selection-background-color: __combo_item_selected_bg__;
                selection-color: __combo_item_selected_text__;
                outline: 0;
                padding: 6px;
            }
            QComboBox QAbstractItemView::item {
                min-height: 32px;
                padding: 6px 8px;
            }
            QComboBox QAbstractItemView::item:hover {
                background-color: __combo_item_hover_bg__;
                color: __combo_item_hover_text__;
            }
            QComboBox QAbstractItemView::item:selected {
                background-color: __combo_item_selected_bg__;
                color: __combo_item_selected_text__;
            }

            QPushButton {
                background-color: __button_bg__;
                color: __button_text__;
                border: 1px solid __button_border__;
                border-radius: 6px;
                padding: 10px 18px;
                min-height: 26px;
                max-height: 44px;
                font-size: 11pt;
                font-weight: 600;
            }
            QPushButton:hover {
                color: __button_hover_text__;
                border: 1px solid __button_hover_border__;
                background-color: __button_hover_bg__;
            }
            QPushButton:pressed {
                border: 1px solid __button_pressed_border__;
                background-color: __button_pressed_bg__;
            }
            QPushButton:disabled {
                background-color: __button_disabled_bg__;
                color: __button_disabled_text__;
                border: 1px solid __button_disabled_border__;
            }

            QProgressBar {
                border: 1px solid __progress_border__;
                border-radius: 6px;
                text-align: center;
                background-color: __progress_bg__;
                color: __progress_text__;
                max-height: 24px;
                font-size: 10pt;
                font-weight: 700;
            }
            QProgressBar::chunk {
                background-color: qlineargradient(
                    x1: 0, y1: 0, x2: 1, y2: 0,
                    stop: 0 __progress_chunk_start__,
                    stop: 1 __progress_chunk_end__
                );
                border-radius: 6px;
            }

            QTextEdit {
                background-color: __log_bg__;
                border: 1px solid __log_border__;
                border-radius: 6px;
                padding: 8px;
                color: __log_text__;
                selection-background-color: __log_selection_bg__;
                selection-color: __log_selection_text__;
            }

            QScrollArea {
                border: none;
            }

            QCheckBox {
                spacing: 5px;
                color: __text__;
            }
            QCheckBox::indicator {
                width: 16px;
                height: 16px;
                border-radius: 3px;
                border: 1px solid __checkbox_border__;
                background-color: __checkbox_bg__;
            }
            QCheckBox::indicator:checked {
                background-color: __checkbox_checked_bg__;
                border: 1px solid __checkbox_checked_bg__;
            }
            QCheckBox::indicator:disabled {
                border: 1px solid __checkbox_disabled_border__;
                background-color: __checkbox_disabled_bg__;
            }

            #startButton {
                background-color: __start_bg__;
                color: __accent_text__;
                border: 1px solid __start_border__;
                font-size: 13pt;
                font-weight: 700;
            }
            #startButton:hover {
                background-color: __start_hover_bg__;
                border: 1px solid __start_hover_border__;
            }
            #startButton:pressed {
                background-color: __start_pressed_bg__;
            }

            #stopButton {
                background-color: __stop_bg__;
                color: __accent_text__;
                border: 1px solid __stop_border__;
                font-size: 12pt;
            }
            #stopButton:hover {
                background-color: __stop_hover_bg__;
                border: 1px solid __stop_hover_border__;
            }
            #stopButton:pressed {
                background-color: __stop_pressed_bg__;
            }

            #shuiyuanButton {
                padding: 6px;
                min-width: 178px;
                max-width: 178px;
                min-height: 42px;
                max-height: 42px;
                background-color: __shuiyuan_bg__;
                border: 1px solid __shuiyuan_border__;
            }
            #shuiyuanButton:hover {
                background-color: __shuiyuan_hover_bg__;
                border: 1px solid __shuiyuan_hover_border__;
            }
            #shuiyuanButton:pressed {
                background-color: __shuiyuan_pressed_bg__;
                border: 1px solid __shuiyuan_pressed_border__;
            }

            #githubButton {
                background-color: __github_bg__;
                color: __github_text__;
                border: 1px solid __github_border__;
                font-weight: 600;
            }
            #githubButton:hover {
                background-color: __github_hover_bg__;
                border: 1px solid __github_hover_border__;
            }
            #githubButton:pressed {
                background-color: __github_pressed_bg__;
            }

            #routeButton, #infoButton, #routePreviewButton {
                background-color: __gold_bg__;
                border: 1px solid __gold_border__;
                color: __gold_text__;
            }
            #routeButton:hover, #infoButton:hover, #routePreviewButton:hover {
                background-color: __gold_hover_bg__;
                border: 1px solid __gold_hover_border__;
            }
            #routeButton:pressed, #infoButton:pressed, #routePreviewButton:pressed {
                background-color: __gold_pressed_bg__;
            }
            #routePreviewButton:disabled {
                background-color: __gold_disabled_bg__;
                color: __gold_disabled_text__;
                border: 1px solid __gold_disabled_border__;
            }

            #deleteRouteButton {
                background-color: __delete_bg__;
                border: 1px solid __delete_border__;
                color: __delete_text__;
                padding: 10px 8px;
            }
            #deleteRouteButton:hover {
                background-color: __delete_hover_bg__;
                border: 1px solid __delete_hover_border__;
            }

            /* 亮暗主题切换（分段控件） */
            #themeSwitch {
                background-color: __switch_bg__;
                border: 1px solid __switch_border__;
                border-radius: 8px;
            }
            #themeLightButton, #themeDarkButton {
                background-color: transparent;
                color: __switch_text__;
                border: none;
                border-radius: 6px;
                padding: 6px 6px;
                min-height: 20px;
                max-height: 30px;
                font-size: 9pt;
                font-weight: 600;
            }
            #themeLightButton:hover, #themeDarkButton:hover {
                background-color: __switch_hover_bg__;
                border: none;
                color: __switch_text__;
            }
            #themeLightButton:checked, #themeDarkButton:checked {
                background-color: __switch_checked_bg__;
                color: __switch_checked_text__;
                border: none;
            }

            QLabel#getCookieLink {
                color: __link__;
                text-decoration: underline;
                padding: 0;
            }
            QLabel#getCookieLink:hover {
                color: __link_hover__;
            }

            QScrollBar:vertical {
                background-color: __scroll_bg__;
                width: 10px;
                margin: 0;
                border: none;
            }
            QScrollBar::handle:vertical {
                background-color: __scroll_handle__;
                min-height: 30px;
                border-radius: 5px;
            }
            QScrollBar::handle:vertical:hover {
                background-color: __scroll_handle_hover__;
            }
            QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
                height: 0;
                border: none;
                background: transparent;
            }

            QToolTip {
                background-color: __tooltip_bg__;
                color: __tooltip_text__;
                border: 1px solid __tooltip_border__;
                padding: 6px;
            }
"""


def main_stylesheet(theme):
    """主窗口样式表（同时被子对话框 / 消息框继承）。"""
    return _fill_tokens(_MAIN_QSS, theme)


_COMMITMENT_QSS = """
            QDialog {
                background-color: __dialog_bg__;
            }
            QLabel#commitmentTitle {
                color: __title_text__;
                font-size: 15pt;
                font-weight: 700;
                background-color: transparent;
            }
            QLabel#commitmentBody {
                background-color: __warn_bg__;
                color: __warn_text__;
                border: 1px solid __warn_border__;
                border-radius: 8px;
                padding: 16px;
                font-size: 10pt;
                line-height: 145%;
            }
            QCheckBox {
                color: __text__;
                font-size: 10pt;
                background-color: transparent;
            }
            QPushButton {
                border: 1px solid __button_border__;
                border-radius: 6px;
                padding: 9px 16px;
                background-color: __button_bg__;
                color: __button_text__;
                font-size: 10pt;
            }
            QPushButton:hover {
                background-color: __button_hover_bg__;
                border: 1px solid __button_hover_border__;
                color: __button_hover_text__;
            }
            QPushButton#commitmentAcceptButton {
                background-color: __accent__;
                border-color: __accent__;
                color: __accent_text__;
                font-weight: 600;
            }
            QPushButton#commitmentAcceptButton:hover {
                background-color: __start_hover_bg__;
                border-color: __start_hover_border__;
                color: __accent_text__;
            }
            QPushButton#commitmentAcceptButton:disabled {
                background-color: __button_disabled_bg__;
                border-color: __button_disabled_border__;
                color: __button_disabled_text__;
            }
"""


def commitment_stylesheet(theme):
    return _fill_tokens(_COMMITMENT_QSS, theme)


_HELP_QSS = """
            #HelpWindow {
                background-color: __window_solid__;
            }
            #contentPanel {
                background-color: __help_panel_bg__;
                border: 1px solid __help_panel_border__;
            }
            #thankYouLabel {
                color: __help_title_text__;
            }
            #infoLabel {
                color: __help_body_text__;
            }
            #versionPill {
                color: __help_pill_text__;
                background-color: __help_pill_bg__;
                border: 1px solid __help_pill_border__;
            }
            #okButton, #checkUpdateButton {
                background-color: __help_button_bg__;
                border: 1px solid __help_button_border__;
                color: __help_button_text__;
            }
            #okButton:hover, #checkUpdateButton:hover {
                background-color: __help_button_hover_bg__;
                border: 1px solid __help_button_hover_border__;
            }
            #checkUpdateButton:disabled {
                color: __help_button_disabled_text__;
                border: 1px solid __help_button_border__;
            }
"""


def help_stylesheet(theme):
    """关于窗口的主题覆盖层（追加在 Ui_HelpWindow 自带样式之后）。"""
    return _fill_tokens(_HELP_QSS, theme)


# ---------------------------------------------------------------- 背景绘制

# 亮色背景 = 原背景照片的"纸面淡彩"版本：灰度 → 反相 → 纸白到墨绿的调色板。
# 反相是刻意为之：原图是偏夜拍的暗素材，直接压白只会糊成一片；反相后原本最亮的
# 灯光与建筑立面变成墨绿层次，原本大片暗部变成纸白，正好是亮色模式要的效果。
LIGHT_BG_GAMMA = 2.0        # 调色板曲线指数，越大越贴近纸白（结构越淡）
LIGHT_BG_OPACITY = 0.95     # 淡彩层整体不透明度
LIGHT_BG_WASH_CENTER = (0.50, 0.34)   # 中心柔化光晕位置（窗口相对坐标）
LIGHT_BG_WASH_RADIUS = 0.72           # 光晕半径 / 窗口长边


def _duotone_color_table(theme):
    """256 级调色板：索引 0 = 墨绿（原图最亮处），索引 255 = 纸白（原图最暗处）。"""
    paper = qcolor(theme["paper_top"])
    ink = qcolor(theme["photo_ink"])
    table = []
    for index in range(256):
        tone = (1.0 - index / 255.0) ** LIGHT_BG_GAMMA
        table.append(qRgba(
            int(paper.red() + (ink.red() - paper.red()) * tone),
            int(paper.green() + (ink.green() - paper.green()) * tone),
            int(paper.blue() + (ink.blue() - paper.blue()) * tone),
            255,
        ))
    return table


class LightBackgroundBrush:
    """把背景照片一次性换算成亮色淡彩图，并缓存缩放结果，避免每次 paint 重复换算。"""

    def __init__(self, source, theme=None):
        theme = theme or LIGHT_THEME
        self._duotone = None
        self._scaled = None
        self._scaled_size = None
        image = None
        if source is not None:
            image = source.toImage() if isinstance(source, QPixmap) else source
        if image is not None and not image.isNull():
            gray = image.convertToFormat(QImage.Format_Grayscale8)
            gray.invertPixels(QImage.InvertMode.InvertRgb)
            indexed = gray.convertToFormat(QImage.Format_Indexed8)
            indexed.setColorTable(_duotone_color_table(theme))
            self._duotone = indexed.convertToFormat(QImage.Format_RGB32)

    def is_valid(self):
        return self._duotone is not None

    def scaled_to(self, size):
        """按目标尺寸等比铺满缩放，同一尺寸直接复用缓存。"""
        if self._duotone is None:
            return None
        if self._scaled is None or self._scaled_size != size:
            self._scaled = self._duotone.scaled(
                size, Qt.KeepAspectRatioByExpanding, Qt.SmoothTransformation)
            self._scaled_size = size
        return self._scaled


def draw_dark_background(painter, rect, theme, background_pixmap):
    """暗色：背景照片 + 渐变暗化遮罩（背景只作氛围，第一眼看到的应是前景 UI）。"""
    if background_pixmap is not None and not background_pixmap.isNull():
        scaled = background_pixmap.scaled(rect.size(), Qt.KeepAspectRatioByExpanding, Qt.SmoothTransformation)
        x = (rect.width() - scaled.width()) // 2
        y = (rect.height() - scaled.height()) // 2
        painter.drawPixmap(x, y, scaled)

        overlay = QLinearGradient(0, 0, 0, max(1, rect.height()))
        overlay.setColorAt(0.0, qcolor(theme["photo_overlay_top"]))
        overlay.setColorAt(1.0, qcolor(theme["photo_overlay_bottom"]))
        painter.fillRect(rect, overlay)
    else:
        painter.fillRect(rect, qcolor(theme["window_solid"]))


def draw_light_background(painter, rect, theme, brush=None):
    """亮色：纸白渐变 + 原照片换算出的淡彩层 + 中心柔化光晕（保证面板处够干净）。"""
    gradient = QLinearGradient(rect.topLeft(), rect.bottomLeft())
    gradient.setColorAt(0.0, qcolor(theme["paper_top"]))
    gradient.setColorAt(1.0, qcolor(theme["paper_bottom"]))
    painter.fillRect(rect, gradient)

    scaled = brush.scaled_to(rect.size()) if brush is not None and brush.is_valid() else None
    if scaled is None:
        return

    painter.save()
    painter.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform)
    painter.setOpacity(LIGHT_BG_OPACITY)
    painter.drawImage(QRect((rect.width() - scaled.width()) // 2,
                            (rect.height() - scaled.height()) // 2,
                            scaled.width(), scaled.height()), scaled)
    painter.setOpacity(1.0)

    wash = QRadialGradient(
        QPointF(rect.left() + rect.width() * LIGHT_BG_WASH_CENTER[0],
                rect.top() + rect.height() * LIGHT_BG_WASH_CENTER[1]),
        max(rect.width(), rect.height()) * LIGHT_BG_WASH_RADIUS)
    wash.setColorAt(0.0, qcolor(theme["bg_wash_inner"]))
    wash.setColorAt(1.0, qcolor(theme["bg_wash_outer"]))
    painter.fillRect(rect, wash)
    painter.restore()

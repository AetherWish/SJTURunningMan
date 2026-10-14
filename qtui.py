import sys
import os
import re
import math
import ctypes
import shutil
import tempfile
import webbrowser
from PySide6.QtWidgets import (
    QApplication, QWidget, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit,
    QPushButton, QTextEdit, QProgressBar, QGroupBox, QDateTimeEdit,
    QMessageBox, QScrollArea, QSizePolicy, QCheckBox, QComboBox,
    QSpacerItem, QFileDialog, QDialog, QFrame, QGraphicsDropShadowEffect
)
from PySide6.QtCore import QThread, Signal, QDateTime, Qt, QUrl, QEvent, QSize, QPropertyAnimation, QEasingCurve, QPointF, QTimer
from PySide6.QtGui import QTextCursor, QFont, QColor, QTextCharFormat, QIcon, QDesktopServices, QPainter, QPixmap, QPen, QPolygonF

from src.main import run_sports_upload
from src.data_generator import generate_running_data_payload
from src.route_preview import build_route_preview, generate_route_preview_html
import src.login as login
from utils.auxiliary_util import SportsUploaderError, get_base_path, get_current_epoch_ms
import src.config as config
import src.theme as theme

from src.info_dialog import HelpWidget

RESOURCES_SUB_DIR = "assets"
ROUTES_SUB_DIR = os.path.join(RESOURCES_SUB_DIR, "Routes")
USER_ROUTES_DIR_NAME = "Routes"
CUSTOM_ROUTE_ACTION = "__custom_route_action__"

GITHUB_REPO_URL = "https://github.com/JackyTJie/SJTURunningMan_Advanced_Edition"
SHUIYUAN_TOPIC_URL = "https://shuiyuan.sjtu.edu.cn/t/topic/421786"
APP_USER_MODEL_ID = "CEQ151.SJTURunningMan.Windows"
DISCLAIMER_TEXT = (
    "本项目仅用于学习、研究和技术测试，主要用于理解运动数据记录与上传相关的技术流程。\n\n"
    "项目开发者反对任何违反学校规定的使用方式。\n\n"
    "请在使用前确认自己的行为符合上海交通大学校规及相关法律法规的要求，"
    "严禁用于伪造运动数据或规避体育锻炼要求。"
)
COMMITMENT_TEXT = (
    "在继续使用本软件前，请认真阅读并作出承诺：\n\n"
    "1. 我理解本项目仅用于学习、研究和技术测试，主要用于理解运动数据记录与上传相关的技术流程。\n\n"
    "2. 我理解项目开发者反对任何违反学校规定的使用方式。\n\n"
    "3. 我承诺在使用前确认自己的行为符合上海交通大学校规及相关法律法规的要求。\n\n"
    "4. 我承诺不会将本软件用于伪造运动数据、规避体育锻炼要求或其他违规操作。"
)


class NoWheelComboBox(QComboBox):
    """Combo box that avoids accidental mouse-wheel selection changes."""

    def wheelEvent(self, event):
        event.ignore()


class GlowButton(QPushButton):
    """Push button with a subtle neon glow on hover and focus."""

    def __init__(self, text="", parent=None, glow_color=None, glow_kind="accent"):
        super().__init__(text, parent)
        self.glow_kind = glow_kind
        self._glow_effect = QGraphicsDropShadowEffect(self)
        self._glow_effect.setOffset(0, 0)
        self._glow_effect.setBlurRadius(0)
        self._glow_effect.setColor(glow_color or QColor(69, 255, 214, 180))
        self.setGraphicsEffect(self._glow_effect)

        self._glow_animation = QPropertyAnimation(self._glow_effect, b"blurRadius", self)
        self._glow_animation.setDuration(170)
        self._glow_animation.setEasingCurve(QEasingCurve.OutCubic)

    def set_glow_color(self, color):
        self._glow_effect.setColor(color)

    def apply_theme_glow(self, theme_tokens):
        self._glow_effect.setColor(theme.glow_color(theme_tokens, self.glow_kind))

    def _animate_glow(self, radius):
        if not self.isEnabled():
            radius = 0
        self._glow_animation.stop()
        self._glow_animation.setStartValue(self._glow_effect.blurRadius())
        self._glow_animation.setEndValue(radius)
        self._glow_animation.start()

    def enterEvent(self, event):
        self._animate_glow(28)
        super().enterEvent(event)

    def leaveEvent(self, event):
        if not self.hasFocus():
            self._animate_glow(0)
        super().leaveEvent(event)

    def focusInEvent(self, event):
        self._animate_glow(24)
        super().focusInEvent(event)

    def focusOutEvent(self, event):
        if not self.underMouse():
            self._animate_glow(0)
        super().focusOutEvent(event)

    def mousePressEvent(self, event):
        self._animate_glow(36)
        super().mousePressEvent(event)

    def mouseReleaseEvent(self, event):
        self._animate_glow(28 if self.underMouse() or self.hasFocus() else 0)
        super().mouseReleaseEvent(event)

    def changeEvent(self, event):
        if event.type() == QEvent.EnabledChange and not self.isEnabled():
            self._animate_glow(0)
        super().changeEvent(event)


def get_resource_path(relative_path):
    """Return a bundled resource path both in source and PyInstaller builds."""
    if hasattr(sys, "_MEIPASS"):
        return os.path.join(sys._MEIPASS, relative_path)
    return os.path.join(get_base_path(), relative_path)


RESOURCES_FULL_PATH = get_resource_path(RESOURCES_SUB_DIR)
APP_ICON_PATH = get_resource_path(os.path.join(RESOURCES_SUB_DIR, "SJTURM.ico"))
if sys.platform == "darwin":
    # Rounded-corner icon for the macOS Dock; Qt uses windowIcon as the dock tile.
    APP_ICON_PATH = get_resource_path(os.path.join(RESOURCES_SUB_DIR, "SJTURM_rounded.png"))
if not os.path.exists(APP_ICON_PATH):
    APP_ICON_PATH = get_resource_path(os.path.join(RESOURCES_SUB_DIR, "SJTURM.png"))
MAIN_BACKGROUND_PATH = get_resource_path(os.path.join(RESOURCES_SUB_DIR, "mainBackground.jpeg"))


def set_windows_app_id():
    """Make Windows taskbar grouping prefer this app's icon."""
    if sys.platform != "win32":
        return
    try:
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(APP_USER_MODEL_ID)
    except Exception:
        return

class WorkerThread(QThread):
    """
    工作线程，用于在后台执行跑步数据上传任务，避免UI冻结。
    """
    progress_update = Signal(int, int, str)
    log_output = Signal(str, str)
    finished = Signal(bool, str)
    route_too_long = Signal(str, str)  # Signal to emit when route is too long
    route_preview_ready = Signal(object)

    def __init__(self, config_data):
        super().__init__()
        self.config_data = config_data
        self._continue_after_route_check = True  # Default to continue execution

    def run(self):
        success = False
        message = "任务已完成。"
        try:
            success, message = run_sports_upload(
                self.config_data,
                progress_callback=self.progress_callback,
                log_cb=self.log_callback,
                stop_check_cb=self.isInterruptionRequested,
                route_preview_cb=self.route_preview_callback
            )
        except SportsUploaderError as e:
            self.log_output.emit(f"任务中断: {e}", "error")
            message = str(e)
            success = False
        except Exception as e:
            self.log_output.emit(f"发生未预期的错误: {e}", "error")
            message = f"未预期的错误: {e}"
            success = False
        finally:
            if self.isInterruptionRequested() and not success:
                 self.finished.emit(False, "任务已手动终止。")
            else:
                 self.finished.emit(success, message)

    def progress_callback(self, current, total, message):
        self.progress_update.emit(current, total, message)

    def log_callback(self, message, level):
        # Check if this is a special route too long message
        if message.startswith("SPECIAL_ROUTE_TOO_LONG:"):
            # Extract distances from the message
            parts = message.split(":")
            if len(parts) >= 3:
                detailed_distance = float(parts[1])
                target_distance = float(parts[2])
                # Set the flag to pause execution
                self._continue_after_route_check = False
                # Emit signal to UI to show route too long dialog
                self.route_too_long.emit(str(detailed_distance), str(target_distance))
                # Wait until the UI sets a flag to continue
                while not self._continue_after_route_check:
                    # Small delay to prevent busy waiting
                    self.msleep(100)
                return  # Don't emit the log message when it was a special route message
        self.log_output.emit(message, level)

    def route_preview_callback(self, preview):
        self.route_preview_ready.emit(preview)


class RoutePreviewThread(QThread):
    """离线生成路线预览的后台线程：无需登录，仅本地补点计算。"""
    preview_ready = Signal(object)
    preview_failed = Signal(str)

    PREVIEW_STATUS = "预览（未上传）"

    def __init__(self, config_data):
        super().__init__()
        self.config_data = config_data

    def run(self):
        try:
            payload, _, _ = generate_running_data_payload(self.config_data, [], {})
            preview = build_route_preview(payload, status=self.PREVIEW_STATUS)
            self.preview_ready.emit(preview)
        except Exception as e:
            self.preview_failed.emit(str(e))


class RouteShapeWidget(QWidget):
    """按坐标绘制所选路线的轮廓折线：无地图瓦片，等比自动缩放。"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self._coords = []
        self._theme = theme.DARK_THEME
        self.setMinimumHeight(140)
        self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.setToolTip("所选路线的坐标轮廓（等比缩放，非地图）")

    def set_coordinates(self, coords):
        self._coords = list(coords or [])
        self.update()

    def set_theme(self, theme_tokens):
        self._theme = dict(theme_tokens)
        self.update()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        if len(self._coords) < 2:
            painter.setPen(theme.qcolor(self._theme["route_placeholder"]))
            painter.drawText(self.rect(), Qt.AlignCenter, "暂无路线坐标")
            return

        rect = self.rect().adjusted(12, 12, -12, -12)
        lons = [lon for lon, _ in self._coords]
        lats = [lat for _, lat in self._coords]
        mid_lat = (min(lats) + max(lats)) / 2.0
        # 经度按纬度余弦折算，保证形状不被横向拉伸
        kx = max(0.2, math.cos(math.radians(mid_lat)))
        span_x = (max(lons) - min(lons)) * kx or 1e-9
        span_y = (max(lats) - min(lats)) or 1e-9
        scale = min(rect.width() / span_x, rect.height() / span_y)
        center_lon = (min(lons) + max(lons)) / 2.0
        center_lat = (min(lats) + max(lats)) / 2.0

        points = []
        for lon, lat in self._coords:
            x = rect.center().x() + (lon - center_lon) * kx * scale
            y = rect.center().y() - (lat - center_lat) * scale
            points.append(QPointF(x, y))

        painter.setPen(QPen(theme.qcolor(self._theme["route_line"]), 2))
        painter.drawPolyline(QPolygonF(points))
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(theme.qcolor(self._theme["route_start"]))
        painter.drawEllipse(points[0], 4, 4)
        painter.setBrush(theme.qcolor(self._theme["route_end"]))
        painter.drawEllipse(points[-1], 4, 4)


class SportsUploaderUI(QWidget):
    def __init__(self):
        super().__init__()
        self.setObjectName("mainWindow")
        self.setWindowTitle("SJTU 校园轻松跑 - Version " + config.global_version)
        self.setWindowIcon(QIcon(APP_ICON_PATH))
        self._main_background_pixmap = QPixmap(MAIN_BACKGROUND_PATH)
        # 亮色背景由这张照片换算得到（灰度 + 反相 + 纸白到墨绿调色板），只做一次
        self._light_background = theme.LightBackgroundBrush(self._main_background_pixmap)
        # 主题：默认跟随系统亮暗，可在标题栏手动切换（选择写入 ui_settings.json）
        self._theme_mode = theme.load_theme_mode()
        self._theme = theme.build_theme(self._theme_mode)
        self._log_entries = []

        # 后台线程引用（私有）
        self._thread = None
        # 关于窗口引用，防止被垃圾回收
        self._help_window = None
        self._latest_route_preview = None
        self._route_preview_temp_files = []

        self.config = {}

        self.init_ui()
        self.apply_theme()
        self.watch_system_color_scheme()

        self.setGeometry(140, 60, 1250, 860)
        self.setMinimumSize(980, 680)

        # 根据当前窗口宽度调整内容区域宽度
        self.adjust_content_width(self.width())
        # 启动时居中主窗口
        try:
            self.center_window()
        except Exception:
            pass

    def apply_theme(self):
        """按当前主题刷新调色板、样式表、按钮辉光、日志配色与背景。"""
        self._theme = theme.build_theme(self._theme_mode)

        theme.apply_palette(self, self._theme)
        app = QApplication.instance()
        if app is not None:
            theme.apply_palette(app, self._theme)

        self.setStyleSheet(theme.main_stylesheet(self._theme))

        for button in self.findChildren(GlowButton):
            button.apply_theme_glow(self._theme)

        if hasattr(self, "route_shape_widget"):
            self.route_shape_widget.set_theme(self._theme)

        self.rebuild_log_output()
        self.sync_theme_switch()
        self.update()

    def set_theme_mode(self, mode):
        """手动切换亮暗主题，并把选择记住到 ui_settings.json。"""
        if mode not in theme.MODES or mode == self._theme_mode:
            return
        self._theme_mode = mode
        theme.save_theme_mode(mode)
        self.apply_theme()

    def sync_theme_switch(self):
        """把高亮落到当前生效的那一档上（跟随系统时高亮系统解析出的亮/暗）。"""
        buttons = getattr(self, "theme_buttons", None)
        if not buttons:
            return
        current = buttons.get(theme.resolve_mode(self._theme_mode))
        if current is not None and not current.isChecked():
            current.setChecked(True)

    def watch_system_color_scheme(self):
        """处于“跟随系统”时，系统亮暗一变就重新取色。"""
        app = QApplication.instance()
        if app is None:
            return
        try:
            app.styleHints().colorSchemeChanged.connect(self.on_system_color_scheme_changed)
        except Exception:
            pass

    def on_system_color_scheme_changed(self, _scheme):
        if self._theme_mode == theme.MODE_FOLLOW:
            self.apply_theme()

    def create_theme_switch(self):
        """标题栏的亮暗切换分段控件：只有「亮 / 暗」两档。

        没有手动选过的时候走系统亮暗，此时高亮的是系统解析出来的那一档；
        一旦点了亮或暗，就固定成该档并记住。
        """
        switch = QFrame()
        switch.setObjectName("themeSwitch")
        switch_layout = QHBoxLayout(switch)
        switch_layout.setContentsMargins(4, 4, 4, 4)
        switch_layout.setSpacing(2)

        object_names = {
            theme.MODE_LIGHT: "themeLightButton",
            theme.MODE_DARK: "themeDarkButton",
        }
        self.theme_buttons = {}
        for mode in theme.SWITCH_MODES:
            button = QPushButton(theme.MODE_SHORT_LABELS[mode])
            button.setObjectName(object_names[mode])
            button.setCheckable(True)
            button.setAutoExclusive(True)
            button.setToolTip(theme.MODE_TOOLTIPS[mode])
            button.clicked.connect(lambda _checked=False, selected=mode: self.set_theme_mode(selected))
            switch_layout.addWidget(button)
            self.theme_buttons[mode] = button

        switch.setToolTip("切换界面亮暗主题（没手动选过之前默认跟随系统的亮暗）")
        return switch

    def create_hint_label(self, text):
        label = QLabel(text)
        label.setObjectName("sectionHint")
        label.setWordWrap(True)
        return label

    def open_github_repo(self):
        QDesktopServices.openUrl(QUrl(GITHUB_REPO_URL))

    def open_shuiyuan_topic(self):
        QDesktopServices.openUrl(QUrl(SHUIYUAN_TOPIC_URL))

    def get_user_routes_dir(self):
        return os.path.join(get_base_path(), USER_ROUTES_DIR_NAME)

    def get_unique_route_destination(self, source_path):
        routes_dir = self.get_user_routes_dir()
        file_name = os.path.basename(source_path)
        stem, ext = os.path.splitext(file_name)
        if not ext:
            ext = ".txt"

        destination_path = os.path.join(routes_dir, f"{stem}{ext}")
        counter = 1
        while os.path.exists(destination_path):
            destination_path = os.path.join(routes_dir, f"{stem}_{counter}{ext}")
            counter += 1
        return destination_path

    def validate_route_file_format(self, file_path):
        """Validate every non-empty route line is longitude,latitude."""
        has_line = False
        with open(file_path, "r", encoding="utf-8") as route_file:
            for line_number, raw_line in enumerate(route_file, start=1):
                line = raw_line.strip()
                if not line:
                    continue

                has_line = True
                parts = [part.strip() for part in line.split(",")]
                if len(parts) != 2:
                    raise ValueError(f"路线文件第 {line_number} 行格式错误，应为 longitude,latitude。")

                try:
                    float(parts[0])
                    float(parts[1])
                except ValueError:
                    raise ValueError(f"路线文件第 {line_number} 行包含非数字坐标。")

        if not has_line:
            raise ValueError("路线文件为空。")

    def get_route_options(self):
        """Return available route options as (display_name, absolute_path)."""
        route_options = []
        base_path = get_base_path()

        user_routes_dir = self.get_user_routes_dir()
        if os.path.isdir(user_routes_dir):
            imported_route_files = [
                os.path.join(user_routes_dir, file_name)
                for file_name in os.listdir(user_routes_dir)
                if file_name.lower().endswith(".txt")
            ]
            imported_route_files.sort(key=lambda path: os.path.basename(path).lower())
            for route_path in imported_route_files:
                route_name = os.path.splitext(os.path.basename(route_path))[0]
                route_options.append((f"{route_name}（已导入）", route_path))

        user_route_path = os.path.join(base_path, "user.txt")
        if os.path.exists(user_route_path):
            route_options.append(("user.txt（自定义路线）", user_route_path))

        routes_dir = get_resource_path(ROUTES_SUB_DIR)
        if os.path.isdir(routes_dir):
            route_files = [
                os.path.join(routes_dir, "default.txt")
            ]
            route_files = [
                route_path
                for route_path in route_files
                if os.path.exists(route_path)
            ]

            for route_path in route_files:
                file_name = os.path.basename(route_path)
                route_name = os.path.splitext(file_name)[0]
                display_name = "default（默认）" if file_name.lower() == "default.txt" else route_name
                route_options.append((display_name, route_path))

        if not route_options:
            fallback_path = os.path.join(base_path, "default.txt")
            if os.path.exists(fallback_path):
                route_options.append(("default（项目根目录）", fallback_path))
            else:
                route_options.append(("硬编码默认路线", ""))

        return route_options

    def populate_route_combo(self, select_path=None):
        self._route_combo_updating = True
        self.route_combo.clear()
        self.route_combo.addItem("自定义...", CUSTOM_ROUTE_ACTION)
        default_index = 1
        selected_index = None
        selected_path_norm = os.path.normcase(os.path.abspath(select_path)) if select_path else None

        for index, (display_name, route_path) in enumerate(self.get_route_options()):
            combo_index = index + 1
            self.route_combo.addItem(display_name, route_path)
            route_path_norm = os.path.normcase(os.path.abspath(route_path)) if route_path else ""
            if selected_path_norm and route_path_norm == selected_path_norm:
                selected_index = combo_index
            if os.path.basename(route_path).lower() == "default.txt":
                default_index = combo_index

        target_index = selected_index if selected_index is not None else min(default_index, self.route_combo.count() - 1)
        self.route_combo.setCurrentIndex(max(0, target_index))
        self._last_route_index = self.route_combo.currentIndex()
        self._route_combo_updating = False
        self.refresh_route_shape()

    def restore_previous_route_selection(self):
        if not hasattr(self, "route_combo"):
            return
        previous_index = getattr(self, "_last_route_index", 0)
        if previous_index < 0 or previous_index >= self.route_combo.count():
            previous_index = 1 if self.route_combo.count() > 1 else 0
        self._route_combo_updating = True
        self.route_combo.setCurrentIndex(previous_index)
        self._route_combo_updating = False

    def import_custom_route(self):
        file_path, _ = QFileDialog.getOpenFileName(
            self,
            "选择自定义路线文件",
            get_base_path(),
            "路线文件 (*.txt)"
        )

        if not file_path:
            self.restore_previous_route_selection()
            return

        if os.path.splitext(file_path)[1].lower() != ".txt":
            QMessageBox.warning(self, "路线文件无效", "请选择 .txt 路线文件。")
            self.restore_previous_route_selection()
            return

        try:
            from src.data_generator import read_gps_coordinates_from_file
            self.validate_route_file_format(file_path)
            coordinates = read_gps_coordinates_from_file(file_path)
            if len(coordinates) < 2:
                raise ValueError("路线文件至少需要包含 2 个有效坐标点。")

            user_routes_dir = self.get_user_routes_dir()
            os.makedirs(user_routes_dir, exist_ok=True)

            source_path = os.path.abspath(file_path)
            target_dir = os.path.abspath(user_routes_dir)
            if os.path.normcase(os.path.dirname(source_path)) == os.path.normcase(target_dir):
                destination_path = source_path
            else:
                destination_path = self.get_unique_route_destination(source_path)
                shutil.copy2(source_path, destination_path)

            self.populate_route_combo(select_path=destination_path)
            QMessageBox.information(self, "路线导入成功", f"已导入路线：{os.path.basename(destination_path)}")
        except Exception as e:
            QMessageBox.warning(self, "路线导入失败", str(e))
            self.restore_previous_route_selection()

    def on_route_combo_changed(self, index):
        if getattr(self, "_route_combo_updating", False):
            return

        route_data = self.route_combo.itemData(index)
        if route_data == CUSTOM_ROUTE_ACTION:
            self.import_custom_route()
            return

        self._last_route_index = index
        self.refresh_route_shape()

    def refresh_route_shape(self):
        """按当前所选路线文件刷新右侧轮廓小图。"""
        if not hasattr(self, "route_shape_widget"):
            return

        coords = []
        route_path = self.route_combo.currentData()
        if isinstance(route_path, str) and route_path and os.path.exists(route_path):
            try:
                from src.data_generator import read_gps_coordinates_from_file
                coords = read_gps_coordinates_from_file(route_path)
            except Exception:
                coords = []
        self.route_shape_widget.set_coordinates(coords)
        self.update_delete_route_button()

    def _selected_route_is_imported(self):
        route_path = self.route_combo.currentData()
        if not isinstance(route_path, str) or not route_path:
            return False
        routes_dir = os.path.abspath(self.get_user_routes_dir())
        return os.path.dirname(os.path.abspath(route_path)) == routes_dir

    def update_delete_route_button(self):
        if hasattr(self, "delete_route_button"):
            self.delete_route_button.setEnabled(self._selected_route_is_imported())

    def delete_selected_route(self):
        """删除选中的已导入路线文件并回退到默认路线。"""
        if not self._selected_route_is_imported():
            return

        route_path = self.route_combo.currentData()
        reply = QMessageBox.question(
            self,
            "删除路线",
            f"确定删除已导入路线文件？\n{os.path.basename(route_path)}\n\n文件删除后不可恢复（可重新导入），选择将回退到默认路线。",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return

        try:
            os.remove(route_path)
            self.log_output_text(f"已删除导入路线: {os.path.basename(route_path)}", "info")
        except OSError as e:
            QMessageBox.warning(self, "删除路线失败", str(e))
            return

        self.populate_route_combo()

    def init_ui(self):
        top_h_layout = QHBoxLayout()
        top_h_layout.setContentsMargins(12, 12, 12, 12)
        top_h_layout.setSpacing(0)

        self.center_widget = QWidget()
        self.center_widget.setObjectName("contentShell")
        main_layout = QVBoxLayout(self.center_widget)
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(0)

        self.scroll_area = QScrollArea()
        self.scroll_area.setObjectName("mainScrollArea")
        self.scroll_area.setFrameShape(QFrame.NoFrame)
        self.scroll_content = QWidget()
        self.scroll_content.setObjectName("scrollContent")
        scroll_layout = QVBoxLayout(self.scroll_content)
        # 外层已有边距，这里保持紧凑避免双重留白
        scroll_layout.setContentsMargins(8, 8, 8, 8)
        scroll_layout.setSpacing(12)
        self.scroll_area.setWidgetResizable(True)
        self.scroll_area.setWidget(self.scroll_content)
        self.scroll_area.viewport().setAutoFillBackground(False)

        main_layout.addWidget(self.scroll_area)

        content_layout = QHBoxLayout()
        content_layout.setContentsMargins(0, 0, 0, 0)
        content_layout.setSpacing(14)

        left_column = QVBoxLayout()
        left_column.setContentsMargins(0, 0, 0, 0)
        left_column.setSpacing(12)

        right_column = QVBoxLayout()
        right_column.setContentsMargins(0, 0, 0, 0)
        right_column.setSpacing(12)

        header = QFrame()
        header.setObjectName("appHeader")
        header_layout = QHBoxLayout(header)
        header_layout.setContentsMargins(14, 10, 14, 10)
        header_layout.setSpacing(10)

        title_block = QVBoxLayout()
        title_block.setContentsMargins(0, 0, 0, 0)
        title_block.setSpacing(0)

        title_label = QLabel("SJTU 校园轻松跑")
        title_label.setObjectName("appTitle")
        title_block.addWidget(title_label)
        header_layout.addLayout(title_block, 1)

        self.theme_switch = self.create_theme_switch()
        header_layout.addWidget(self.theme_switch)

        self.shuiyuan_button = GlowButton(glow_kind="accent")
        self.shuiyuan_button.setObjectName("shuiyuanButton")
        shuiyuan_icon_path = os.path.join(RESOURCES_FULL_PATH, "shuiyuan_logo.svg")
        if os.path.exists(shuiyuan_icon_path):
            self.shuiyuan_button.setIcon(QIcon(shuiyuan_icon_path))
            self.shuiyuan_button.setIconSize(QSize(128, 128))
        else:
            self.shuiyuan_button.setText("水源")
        self.shuiyuan_button.setToolTip("打开水源社区讨论帖")
        self.shuiyuan_button.clicked.connect(self.open_shuiyuan_topic)
        header_layout.addWidget(self.shuiyuan_button)

        self.github_button = GlowButton("GitHub", glow_kind="info")
        self.github_button.setObjectName("githubButton")
        github_icon_path = os.path.join(RESOURCES_FULL_PATH, "github-mark.svg")
        if os.path.exists(github_icon_path):
            self.github_button.setIcon(QIcon(github_icon_path))
        self.github_button.setToolTip("打开项目 GitHub 仓库")
        self.github_button.clicked.connect(self.open_github_repo)
        header_layout.addWidget(self.github_button)
        left_column.addWidget(header)

        user_group = QGroupBox("用户配置")
        user_row_layout = QHBoxLayout()
        user_row_layout.setSpacing(14)
        user_row_layout.setContentsMargins(12, 12, 12, 12)

        username_layout = QVBoxLayout()
        username_layout.setSpacing(6)
        username_label_layout = QHBoxLayout()
        username_label_layout.addWidget(QLabel("用户名:"))
        username_label_layout.addStretch()
        username_layout.addLayout(username_label_layout)

        self.username_input = QLineEdit()
        self.username_input.setPlaceholderText("Jaccount用户名")
        username_layout.addWidget(self.username_input)

        password_layout = QVBoxLayout()
        password_layout.setSpacing(6)
        password_label_layout = QHBoxLayout()
        password_label_layout.addWidget(QLabel("密码:"))
        password_label_layout.addStretch()
        password_layout.addLayout(password_label_layout)

        self.password_input = QLineEdit()
        self.password_input.setPlaceholderText("密码")
        self.password_input.setEchoMode(QLineEdit.Password)
        password_layout.addWidget(self.password_input)

        user_row_layout.addLayout(username_layout, 1)
        user_row_layout.addLayout(password_layout, 1)
        user_group.setLayout(user_row_layout)
        left_column.addWidget(user_group)

        status_group = QGroupBox("程序状态")
        status_layout = QVBoxLayout()
        status_layout.setContentsMargins(12, 12, 12, 12)
        status_layout.setSpacing(10)

        self.progress_bar = QProgressBar()
        self.progress_bar.setValue(0)
        status_layout.addWidget(self.progress_bar)

        self.status_label = QLabel("状态: 待命")
        status_layout.addWidget(self.status_label)

        self.warning_label = QLabel(DISCLAIMER_TEXT)
        self.warning_label.setObjectName("warningBox")
        self.warning_label.setWordWrap(True)
        self.warning_label.setAlignment(Qt.AlignCenter)
        self.warning_label.setMinimumHeight(260)
        self.warning_label.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        status_layout.addWidget(self.warning_label, 1)

        self.log_output_area = QTextEdit()
        self.log_output_area.setReadOnly(True)
        self.log_output_area.setFont(QFont("Monospace", 10))
        self.log_output_area.setMinimumHeight(260)
        self.log_output_area.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.log_output_area.setVisible(False)
        status_layout.addWidget(self.log_output_area, 1)

        status_group.setLayout(status_layout)
        left_column.addWidget(status_group, 1)

        # 添加运行次数和时间选择组件
        run_settings_group = QGroupBox("上传设置")
        run_settings_layout = QVBoxLayout()
        run_settings_layout.setContentsMargins(12, 12, 12, 12)
        run_settings_layout.setSpacing(12)

        # 跑步次数
        days_layout = QVBoxLayout()
        days_layout.setSpacing(6)
        days_label_layout = QHBoxLayout()
        days_label_layout.addWidget(QLabel("跑步次数:"))
        days_label_layout.addStretch()
        days_layout.addLayout(days_label_layout)

        days_input_layout = QHBoxLayout()
        self.run_days_input = QLineEdit()
        self.run_days_input.setText("1")
        self.run_days_input.setPlaceholderText("正整数，最多 30")
        self.run_days_input.setMaxLength(2)
        self.run_days_input.setToolTip("要生成的跑步记录数量，最多 30 条。")
        days_input_layout.addWidget(self.run_days_input)
        days_layout.addLayout(days_input_layout)
        days_layout.addWidget(self.create_hint_label("最多 30 条。"))

        # 跑步开始时间
        time_layout = QVBoxLayout()
        time_layout.setSpacing(6)
        time_label_layout = QHBoxLayout()
        time_label_layout.addWidget(QLabel("跑步时间:"))
        time_label_layout.addStretch()
        time_layout.addLayout(time_label_layout)

        time_input_layout = QHBoxLayout()
        self.run_time_input = QLineEdit()
        self.run_time_input.setText("08:00:00")
        self.run_time_input.setMaxLength(8)
        self.run_time_input.setPlaceholderText("HH:MM:SS，例如 08:00:00")
        self.run_time_input.setToolTip("记录的基础开始时间；实际生成时会自动加入随机偏移。")
        time_input_layout.addWidget(self.run_time_input)

        time_layout.addLayout(time_input_layout)
        time_layout.addWidget(self.create_hint_label("格式：HH:MM:SS，实际会随机偏移。"))

        first_settings_row = QHBoxLayout()
        first_settings_row.setSpacing(14)
        first_settings_row.addLayout(days_layout, 1)
        first_settings_row.addLayout(time_layout, 1)
        first_settings_row.setAlignment(days_layout, Qt.AlignTop)
        first_settings_row.setAlignment(time_layout, Qt.AlignTop)
        run_settings_layout.addLayout(first_settings_row)

        # 结束日期
        date_layout = QVBoxLayout()
        date_layout.setSpacing(6)
        date_label_layout = QHBoxLayout()
        date_label_layout.addWidget(QLabel("结束日期:"))
        date_label_layout.addStretch()
        date_layout.addLayout(date_label_layout)

        date_input_layout = QHBoxLayout()
        from datetime import datetime, timedelta
        yesterday = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')
        self.date_input = QLineEdit()
        self.date_input.setText(yesterday)
        self.date_input.setMaxLength(10)
        self.date_input.setPlaceholderText("YYYY-MM-DD，例如 2026-05-07")
        self.date_input.setToolTip("最新一条记录的日期；程序会从这一天向前生成记录。")
        date_input_layout.addWidget(self.date_input)

        date_layout.addLayout(date_input_layout)
        date_layout.addWidget(self.create_hint_label("格式：YYYY-MM-DD，作为最新一条记录。"))

        # 跑步距离
        distance_layout = QVBoxLayout()
        distance_layout.setSpacing(6)
        distance_label_layout = QHBoxLayout()
        distance_label_layout.addWidget(QLabel("跑步距离:"))
        distance_label_layout.addStretch()
        distance_layout.addLayout(distance_label_layout)

        distance_input_layout = QHBoxLayout()
        self.run_distance_input = QLineEdit()
        self.run_distance_input.setText("4")
        self.run_distance_input.setPlaceholderText("1-5，单位 km")
        self.run_distance_input.setMaxLength(3)
        self.run_distance_input.setToolTip("每条记录的目标跑步距离，最多 5km。")
        distance_input_layout.addWidget(self.run_distance_input)
        distance_layout.addLayout(distance_input_layout)
        distance_layout.addWidget(self.create_hint_label("单位 km，最多 5km。"))

        second_settings_row = QHBoxLayout()
        second_settings_row.setSpacing(14)
        second_settings_row.addLayout(date_layout, 1)
        second_settings_row.addLayout(distance_layout, 1)
        second_settings_row.setAlignment(date_layout, Qt.AlignTop)
        second_settings_row.setAlignment(distance_layout, Qt.AlignTop)
        run_settings_layout.addLayout(second_settings_row)

        # 预设路线
        route_layout = QVBoxLayout()
        route_layout.setSpacing(6)
        route_label_layout = QHBoxLayout()
        route_label_layout.addWidget(QLabel("预设路线:"))
        route_label_layout.addStretch()
        route_layout.addLayout(route_label_layout)

        self.route_combo = NoWheelComboBox()
        self.route_combo.setToolTip("选择本次生成记录使用的路线。")
        self.populate_route_combo()
        self.route_combo.currentIndexChanged.connect(self.on_route_combo_changed)

        self.delete_route_button = GlowButton("删除", glow_kind="danger")
        self.delete_route_button.setObjectName("deleteRouteButton")
        self.delete_route_button.setFixedWidth(64)
        self.delete_route_button.setToolTip("删除当前选中的已导入路线文件；内置 default 和旧版 user.txt 不可删除。")
        self.delete_route_button.setEnabled(False)
        self.delete_route_button.clicked.connect(self.delete_selected_route)

        route_input_layout = QHBoxLayout()
        route_input_layout.setSpacing(8)
        route_input_layout.addWidget(self.route_combo, 1)
        route_input_layout.addWidget(self.delete_route_button)
        route_layout.addLayout(route_input_layout)
        route_layout.addWidget(self.create_hint_label("内置路线暂仅保留 default；其他路线待校验后恢复，也可选择“自定义...”导入 txt，导入后可用“删除”移除。"))

        run_settings_layout.addLayout(route_layout)

        run_settings_group.setLayout(run_settings_layout)
        right_column.addWidget(run_settings_group)

        action_button_layout = QVBoxLayout()
        action_button_layout.setSpacing(10)
        primary_button_layout = QHBoxLayout()
        primary_button_layout.setSpacing(12)
        secondary_button_layout = QHBoxLayout()
        secondary_button_layout.setSpacing(12)

        self.start_button = GlowButton("开始生成并上传", glow_kind="accent")
        self.start_button.setObjectName("startButton")
        self.start_button.clicked.connect(self.start_upload)
        primary_button_layout.addWidget(self.start_button)

        self.stop_button = GlowButton("停止任务", glow_kind="danger")
        self.stop_button.setObjectName("stopButton")
        self.stop_button.setEnabled(False)
        self.stop_button.clicked.connect(self.stop_upload)
        primary_button_layout.addWidget(self.stop_button)

        self.route_button = GlowButton("设计/更新路线", glow_kind="warn")
        self.route_button.setObjectName("routeButton")
        self.route_button.setToolTip("打开路线规划器生成 txt；生成后在“预设路线”中选择“自定义...”导入。")
        self.route_button.clicked.connect(self.open_route_generator)
        secondary_button_layout.addWidget(self.route_button)

        self.info_button = GlowButton("说明", glow_kind="warn")
        self.info_button.setObjectName("infoButton")
        self.info_button.clicked.connect(self.show_info_dialog)
        secondary_button_layout.addWidget(self.info_button)

        action_button_layout.addLayout(primary_button_layout)
        action_button_layout.addLayout(secondary_button_layout)

        right_column.addLayout(action_button_layout)
        route_generator_hint = self.create_hint_label("需要新路线时点击“设计/更新路线”，生成 txt 后通过“预设路线”里的“自定义...”导入。")
        route_generator_hint.setObjectName("floatingHint")
        right_column.addWidget(route_generator_hint)

        route_preview_group = QGroupBox("路线预览")
        route_preview_layout = QHBoxLayout()
        route_preview_layout.setContentsMargins(12, 12, 12, 12)
        route_preview_layout.setSpacing(12)

        preview_left_layout = QVBoxLayout()
        preview_left_layout.setSpacing(8)

        self.route_preview_summary_label = QLabel("上传前点击“预览路线”，即可在浏览器地图中查看按当前设置补点生成的路线。")
        self.route_preview_summary_label.setObjectName("sectionHint")
        self.route_preview_summary_label.setWordWrap(True)
        preview_left_layout.addWidget(self.route_preview_summary_label)

        self.route_preview_button = GlowButton("预览路线", glow_kind="warn")
        self.route_preview_button.setObjectName("routePreviewButton")
        self.route_preview_button.setToolTip("按当前设置离线生成补点路线并在浏览器地图中预览；上传过程中/结束后显示实际上传轨迹。")
        self.route_preview_button.clicked.connect(self.show_route_preview)
        preview_left_layout.addWidget(self.route_preview_button)

        map_provider_row = QHBoxLayout()
        map_provider_row.setSpacing(8)
        map_provider_row.addWidget(QLabel("地图引擎:"))
        self.map_provider_combo = NoWheelComboBox()
        self.map_provider_combo.addItem("百度地图（默认）", "baidu")
        self.map_provider_combo.addItem("OpenStreetMap", "osm")
        self.map_provider_combo.setToolTip("路线规划器和路线预览使用的地图引擎；百度为默认。")
        map_provider_row.addWidget(self.map_provider_combo, 1)
        preview_left_layout.addLayout(map_provider_row)
        preview_left_layout.addStretch(1)

        self.route_shape_widget = RouteShapeWidget()
        route_preview_layout.addLayout(preview_left_layout, 2)
        route_preview_layout.addWidget(self.route_shape_widget, 3)

        route_preview_group.setLayout(route_preview_layout)
        # 与左列“程序状态”同用 stretch 1，两列底边对齐
        right_column.addWidget(route_preview_group, 1)
        self.refresh_route_shape()

        content_layout.addLayout(left_column, 5)
        content_layout.addLayout(right_column, 4)
        scroll_layout.addLayout(content_layout)

        top_h_layout.addWidget(self.center_widget)

        self.setLayout(top_h_layout)

    def paintEvent(self, event):
        """暗色沿用背景照片 + 暗化遮罩；亮色改用纸白底 + 交大庙门线描。"""
        painter = QPainter(self)
        if self._theme["mode"] == theme.MODE_LIGHT:
            theme.draw_light_background(painter, self.rect(), self._theme, self._light_background)
        else:
            theme.draw_dark_background(
                painter,
                self.rect(),
                self._theme,
                getattr(self, "_main_background_pixmap", QPixmap()),
            )
        super().paintEvent(event)

    def resizeEvent(self, event):
        """
        槽函数，用于处理窗口大小调整事件。
        根据窗口宽度调整内部内容区域的最大宽度。
        """
        super().resizeEvent(event)
        self.adjust_content_width(event.size().width())

    def adjust_content_width(self, window_width):
        """
        根据给定的窗口宽度，计算并设置 center_widget 的固定宽度。
        """
        # 内容区尽量占满窗口宽度，只留外层窄边距，减少两侧空白。
        available_width = max(0, window_width - 24)
        calculated_width = int(min(available_width, 1320))
        calculated_width = max(940, calculated_width)
        self.center_widget.setFixedWidth(calculated_width)

    def center_window(self):
        """将主窗口居中到主显示器的可用区域中心。"""
        try:
            screen = QApplication.primaryScreen()
            if screen is None:
                return
            available = screen.availableGeometry()

            fg = self.frameGeometry()
            fg.moveCenter(available.center())
            self.move(fg.topLeft())
        except Exception:
            return

    def get_settings_from_ui(self, require_credentials=True):
        """从UI获取当前配置并返回字典；require_credentials=False 用于离线预览，跳过登录校验。"""
        try:
            username = self.username_input.text().strip()
            password = self.password_input.text()

            # 获取跑步次数、跑步时间和距离
            run_days_text = self.run_days_input.text().strip()
            if not re.fullmatch(r"\d+", run_days_text):
                raise ValueError("跑步次数应为正整数，例如 5")
            run_times = int(run_days_text)
            if not (1 <= run_times <= 30):
                raise ValueError("跑步次数应在 1-30 之间")

            run_time_text = self.run_time_input.text().strip()
            if not re.fullmatch(r"\d{2}:\d{2}:\d{2}", run_time_text):
                raise ValueError("时间格式应为 HH:MM:SS，例如 08:00:00")
            run_hour, run_minute, run_second = [int(part) for part in run_time_text.split(":")]
            if not (0 <= run_hour <= 23 and 0 <= run_minute <= 59 and 0 <= run_second <= 59):
                raise ValueError("时间范围无效，小时应为 00-23，分钟和秒应为 00-59")

            run_distance_text = self.run_distance_input.text().strip()
            try:
                run_distance_km = float(run_distance_text)
            except ValueError:
                raise ValueError("距离应为数字，单位 km，例如 3 或 4")
            if not (0 < run_distance_km <= 5):
                raise ValueError("距离应大于 0 且不超过 5km")
            if run_distance_km.is_integer():
                run_distance_km = int(run_distance_km)

            selected_route_path = ""
            selected_route_name = ""
            if hasattr(self, "route_combo"):
                selected_route_path = self.route_combo.currentData() or ""
                selected_route_name = self.route_combo.currentText().strip()
                if selected_route_path == CUSTOM_ROUTE_ACTION:
                    selected_route_path = ""
                    selected_route_name = ""

            current_config = {
                "USER_ID": username,
                "PASSWORD": password,
                "RUN_TIMES": run_times,  # 添加运行次数配置
                "RUN_HOUR": run_hour,    # 添加运行小时配置
                "RUN_MINUTE": run_minute,    # 添加运行分钟配置
                "RUN_SECOND": run_second,    # 添加运行秒钟配置
                "RUN_DISTANCE_KM": run_distance_km,  # 添加运行距离配置
                "START_LATITUDE": float(self.config.get("START_LATITUDE", 31.031599)),
                "START_LONGITUDE": float(self.config.get("START_LONGITUDE", 121.442938)),
                "END_LATITUDE": float(self.config.get("END_LATITUDE", 31.0264)),
                "END_LONGITUDE": float(self.config.get("END_LONGITUDE", 121.4551)),
                "RUNNING_SPEED_MPS": round(1000.0 / (4.0 * 60), 3),  # 4分配对应的速度，约4.17 m/s
                "INTERVAL_SECONDS": int(self.config.get("INTERVAL_SECONDS", 3)),
                "HOST": "pe.sjtu.edu.cn",
                "UID_URL": "https://pe.sjtu.edu.cn/sports/my/uid",
                "MY_DATA_URL": "https://pe.sjtu.edu.cn/sports/my/data",
                "POINT_RULE_URL": "https://pe.sjtu.edu.cn/api/running/point-rule",  # Fixed URL
                "UPLOAD_URL": "https://pe.sjtu.edu.cn/api/running/result/upload"
            }

            if selected_route_path:
                current_config["ROUTE_PATH"] = selected_route_path
                current_config["ROUTE_NAME"] = selected_route_name

            # Add start date from direct input (the input is always filled with a default value)
            start_date_text = self.date_input.text().strip()
            if start_date_text:
                try:
                    from datetime import datetime
                    parsed_date = datetime.strptime(start_date_text, '%Y-%m-%d')
                    current_config["START_DATE"] = parsed_date.strftime('%Y-%m-%d')
                except ValueError:
                    raise ValueError("日期格式应为 YYYY-MM-DD，例如 2026-05-07")

            # START_TIME_EPOCH_MS 由后端生成，不从 UI 获取

            if require_credentials:
                if not current_config["USER_ID"] or not current_config["PASSWORD"]:
                    raise ValueError("用户名和密码不能为空。")
            elif not current_config["USER_ID"]:
                current_config["USER_ID"] = "preview"

            return current_config

        except ValueError as e:
            raise ValueError(f"输入错误: {e}")
        except Exception as e:
            raise Exception(f"获取配置时发生未知错误: {e}")

    def _2fa_select_method(self):
        """二次验证：让用户选择验证方式"""
        dialog = QDialog(self)
        dialog.setWindowTitle("异地登录验证")
        dialog.setWindowFlags(Qt.Dialog | Qt.WindowCloseButtonHint)
        dialog.setFixedSize(360, 180)
        dialog.setWindowModality(Qt.WindowModal)

        layout = QVBoxLayout(dialog)
        layout.setContentsMargins(24, 20, 24, 20)
        layout.setSpacing(14)

        label = QLabel("请选择验证方式:")
        label.setStyleSheet("font-size: 11pt;")
        layout.addWidget(label)

        combo = QComboBox()
        combo.addItems(["交我办消息", "邮箱", "短信"])
        combo.setStyleSheet("padding: 6px; font-size: 10pt;")
        layout.addWidget(combo)

        btn_layout = QHBoxLayout()
        btn_layout.addStretch()
        ok_btn = QPushButton("确定")
        ok_btn.setFixedWidth(80)
        ok_btn.clicked.connect(dialog.accept)
        cancel_btn = QPushButton("取消")
        cancel_btn.setFixedWidth(80)
        cancel_btn.clicked.connect(dialog.reject)
        btn_layout.addWidget(ok_btn)
        btn_layout.addWidget(cancel_btn)
        layout.addLayout(btn_layout)

        method_map = {"交我办消息": "app", "邮箱": "email", "短信": "sms"}
        if dialog.exec() == QDialog.Accepted:
            return method_map.get(combo.currentText(), "app")
        return None

    def _2fa_get_code(self):
        """二次验证：获取用户输入的验证码"""
        dialog = QDialog(self)
        dialog.setWindowTitle("输入验证码")
        dialog.setWindowFlags(Qt.Dialog | Qt.WindowCloseButtonHint)
        dialog.setFixedSize(360, 180)
        dialog.setWindowModality(Qt.WindowModal)

        layout = QVBoxLayout(dialog)
        layout.setContentsMargins(24, 20, 24, 20)
        layout.setSpacing(14)

        label = QLabel("请输入6位验证码（输入 r 可重新发送）:")
        label.setStyleSheet("font-size: 11pt;")
        layout.addWidget(label)

        line_edit = QLineEdit()
        line_edit.setPlaceholderText("验证码")
        line_edit.setStyleSheet("padding: 6px; font-size: 10pt;")
        layout.addWidget(line_edit)

        btn_layout = QHBoxLayout()
        btn_layout.addStretch()
        ok_btn = QPushButton("确定")
        ok_btn.setFixedWidth(80)
        ok_btn.clicked.connect(dialog.accept)
        cancel_btn = QPushButton("取消")
        cancel_btn.setFixedWidth(80)
        cancel_btn.clicked.connect(dialog.reject)
        btn_layout.addWidget(ok_btn)
        btn_layout.addWidget(cancel_btn)
        layout.addLayout(btn_layout)

        if dialog.exec() == QDialog.Accepted:
            code = line_edit.text().strip()
            return code if code else None
        return None

    def _2fa_show_message(self, msg):
        """二次验证：显示提示信息"""
        self.log_output_text(msg, "info")

    def show_commitment_dialog(self):
        """Require an explicit compliance commitment before the main window is usable."""
        dialog = QDialog(self)
        dialog.setWindowTitle("使用承诺书")
        dialog.setWindowFlags(Qt.Dialog | Qt.WindowCloseButtonHint)
        dialog.setWindowModality(Qt.ApplicationModal)
        dialog.setMinimumWidth(560)
        dialog.setStyleSheet(theme.commitment_stylesheet(self._theme))

        layout = QVBoxLayout(dialog)
        layout.setContentsMargins(24, 24, 24, 20)
        layout.setSpacing(16)

        title_label = QLabel("使用承诺书")
        title_label.setObjectName("commitmentTitle")
        layout.addWidget(title_label)

        body_label = QLabel(COMMITMENT_TEXT)
        body_label.setObjectName("commitmentBody")
        body_label.setWordWrap(True)
        body_label.setMinimumHeight(220)
        layout.addWidget(body_label)

        commitment_checkbox = QCheckBox("我已阅读以上内容，并承诺不会将本软件用于任何违规操作。")
        layout.addWidget(commitment_checkbox)

        button_layout = QHBoxLayout()
        button_layout.addStretch()

        exit_button = QPushButton("退出")
        exit_button.clicked.connect(dialog.reject)
        button_layout.addWidget(exit_button)

        accept_button = QPushButton("我承诺，进入软件")
        accept_button.setObjectName("commitmentAcceptButton")
        accept_button.setEnabled(False)
        accept_button.clicked.connect(dialog.accept)
        accept_button.setDefault(True)
        commitment_checkbox.toggled.connect(accept_button.setEnabled)
        button_layout.addWidget(accept_button)

        layout.addLayout(button_layout)

        return dialog.exec() == QDialog.Accepted

    def show_program_log(self):
        """Switch the status area from the startup warning to runtime logs."""
        if hasattr(self, "warning_label"):
            self.warning_label.setVisible(False)
        if hasattr(self, "log_output_area"):
            self.log_output_area.setVisible(True)

    def start_upload(self):
        self.show_program_log()
        self.clear_log_output()
        self.progress_bar.setValue(0)
        self.status_label.setText("状态: 准备中...")
        self.log_output_text("准备开始上传...", "info")

        try:
            current_config_to_send = self.get_settings_from_ui()
        except (ValueError, Exception) as e:
            self.log_output_text(f"配置错误: {e}", "error")
            self.status_label.setText("状态: 错误")
            return

        self.start_button.setEnabled(False)
        self.stop_button.setEnabled(False)
        self.info_button.setEnabled(False)

        # 调用 login.py 获取 session，使用 UI 中的用户名/密码
        try:
            username = current_config_to_send.get("USER_ID")
            password = current_config_to_send.get("PASSWORD")

            two_fa_cb = {
                'select_method': self._2fa_select_method,
                'get_code': self._2fa_get_code,
                'show_message': self._2fa_show_message,
            }

            session = login.login(username, password, two_fa_cb=two_fa_cb)
            current_config_to_send["SESSION"] = session
            current_config_to_send["USER_ID"] = username
        except Exception as e:
            self.log_output_text(f"登录失败: {e}", "error")
            self.start_button.setEnabled(True)
            self.stop_button.setEnabled(False)
            self.username_input.setEnabled(True)
            self.password_input.setEnabled(True)
            self.info_button.setEnabled(True)
            QMessageBox.critical(self, "登录失败", str(e))
            return

        self.stop_button.setEnabled(True)
        self.username_input.setEnabled(False)
        self.password_input.setEnabled(False)

        # Check if current route exceeds target distance and ask user what to do
        try:
            from src.data_generator import read_gps_coordinates_from_file, calculate_route_distance
            import os
            
            from utils.auxiliary_util import get_base_path
            base_path = get_base_path()
            route_path = current_config_to_send.get("ROUTE_PATH")

            if not route_path:
                user_loc_path = os.path.join(base_path, 'user.txt')
                default_loc_path = os.path.join(base_path, 'default.txt')
                route_path = default_loc_path
                if os.path.exists(user_loc_path):
                    route_path = user_loc_path
                elif not os.path.exists(route_path):
                    route_path = ""

            if not route_path or not os.path.exists(route_path):
                raise Exception(f"当前路线文件不存在: {route_path or '未选择路线文件'}")

            route_coordinates = read_gps_coordinates_from_file(route_path)
            route_distance = calculate_route_distance(route_coordinates)
            if current_config_to_send.get("ROUTE_NAME"):
                self.log_output_text(f"当前选择路线: {current_config_to_send['ROUTE_NAME']}", "info")
            target_distance_m = current_config_to_send.get('RUN_DISTANCE_KM', 5) * 1000  # Convert to meters
            
            if route_distance > target_distance_m:
                from PySide6.QtWidgets import QMessageBox
                reply = QMessageBox.question(self, "路线距离提醒", 
                                           f"当前路线长度为 {route_distance/1000:.2f}km，"
                                           f"超过了您选择的 {current_config_to_send.get('RUN_DISTANCE_KM', 5)}km。\n\n"
                                           f"您希望：\n"
                                           f"  - 选择\"是\"：自动削减路线至目标距离\n"
                                           f"  - 选择\"否\"：按照完整路线进行跑步",
                                           QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                                           QMessageBox.StandardButton.Yes)
                
                if reply == QMessageBox.StandardButton.Yes:
                    # User wants to truncate to target distance
                    self.log_output_text("用户选择自动削减路线至目标距离", "info")
                else:
                    # User wants to continue with full route
                    self.log_output_text("用户选择按照完整路线进行跑步", "info")
                    # Update the target distance to be the actual route distance
                    # We need to adjust the RUN_DISTANCE_KM to match the route distance
                    current_config_to_send['RUN_DISTANCE_KM'] = round(route_distance / 1000, 2)
                    self.log_output_text(f"已更新跑步距离至 {current_config_to_send['RUN_DISTANCE_KM']}km", "info")
        except Exception as e:
            self.log_output_text(f"检查路线距离时出现错误: {e}", "error")
            # Continue anyway, don't block the upload for this check

        self._thread = WorkerThread(current_config_to_send)
        self._thread.progress_update.connect(self.update_progress)
        self._thread.log_output.connect(self.log_output_text)
        self._thread.route_too_long.connect(self.handle_route_too_long)
        self._thread.route_preview_ready.connect(self.handle_route_preview_ready)
        self._thread.finished.connect(self.upload_finished)
        self._thread.start()

    def handle_route_too_long(self, detailed_distance_str, target_distance_str):
        """Handle when the route is too long by showing a dialog to the user."""
        detailed_distance = float(detailed_distance_str)
        target_distance = float(target_distance_str)
        
        # Show a message box to the user
        reply = QMessageBox.question(
            self, 
            "路线距离提醒", 
            f"当前路线长度为 {detailed_distance/1000:.2f}km，"
            f"超过了您选择的 {target_distance/1000:.2f}km。\n\n"
            f"您希望：\n"
            f"  - 选择\"是\"：自动削减路线至目标距离\n"
            f"  - 选择\"否\"：按照完整路线继续跑步\n"
            f"  - 选择\"取消\"：停止当前任务",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No | QMessageBox.StandardButton.Cancel,
            QMessageBox.StandardButton.Yes
        )
        
        if reply == QMessageBox.StandardButton.Yes:
            # User wants to truncate to target distance - set flag to continue
            if self._thread:
                self._thread._continue_after_route_check = True
                self.log_output_text("用户选择自动削减路线至目标距离", "info")
        elif reply == QMessageBox.StandardButton.No:
            # User wants to continue with full route - set flag to continue
            if self._thread:
                self._thread._continue_after_route_check = True
                self.log_output_text("用户选择按照完整路线进行跑步", "info")
        else:  # Cancel
            # User wants to stop - interrupt the thread
            if self._thread and self._thread.isRunning():
                self._thread.requestInterruption()
                self.log_output_text("用户选择停止任务", "info")
                self.stop_button.setEnabled(False)
                self.status_label.setText("状态: 正在停止...")

    def handle_route_preview_ready(self, preview):
        self._latest_route_preview = preview
        summary = preview.get("summary", "暂无可预览路线") if isinstance(preview, dict) else "暂无可预览路线"
        if hasattr(self, "route_preview_summary_label"):
            self.route_preview_summary_label.setText(summary)

    def show_route_preview(self):
        preview = getattr(self, "_latest_route_preview", None)
        if (
            isinstance(preview, dict)
            and preview.get("available")
            and preview.get("status") != RoutePreviewThread.PREVIEW_STATUS
        ):
            # 来自上传流程的实际轨迹，直接打开
            self.open_route_preview(preview)
            return
        # 上传前：按当前设置离线生成一遍补点路线再预览
        self.generate_route_preview_offline()

    def generate_route_preview_offline(self):
        if getattr(self, "_preview_thread", None) and self._preview_thread.isRunning():
            return

        try:
            preview_config = self.get_settings_from_ui(require_credentials=False)
        except Exception as e:
            self.log_output_text(f"预览配置错误: {e}", "error")
            QMessageBox.warning(self, "路线预览", f"配置错误: {e}")
            return

        preview_config["START_TIME_EPOCH_MS"] = get_current_epoch_ms()
        self.route_preview_button.setEnabled(False)
        self.route_preview_summary_label.setText("正在生成预览路线...")

        self._preview_thread = RoutePreviewThread(preview_config)
        self._preview_thread.preview_ready.connect(self.handle_offline_preview_ready)
        self._preview_thread.preview_failed.connect(self.handle_offline_preview_failed)
        self._preview_thread.start()

    def handle_offline_preview_ready(self, preview):
        self.route_preview_button.setEnabled(True)
        if isinstance(preview, dict) and preview.get("available"):
            self.route_preview_summary_label.setText(preview.get("summary", ""))
            self.open_route_preview(preview)
        else:
            self.route_preview_summary_label.setText("未能生成可预览路线。")
            QMessageBox.information(self, "路线预览", "未能生成可预览路线，请检查路线文件与设置。")

    def handle_offline_preview_failed(self, message):
        self.route_preview_button.setEnabled(True)
        self.route_preview_summary_label.setText("预览生成失败。")
        self.log_output_text(f"生成路线预览失败: {message}", "error")
        QMessageBox.warning(self, "路线预览", f"生成失败: {message}")

    def open_route_preview(self, preview):
        try:
            provider = self.map_provider_combo.currentData() if hasattr(self, "map_provider_combo") else "baidu"
            html_content = generate_route_preview_html(preview, provider=provider)
            temp_path = self.write_route_preview_html(html_content)
            webbrowser.open(QUrl.fromLocalFile(temp_path).toString())
            self.log_output_text("已在系统浏览器中打开路线预览。", "info")
        except Exception as e:
            self.log_output_text(f"无法打开路线预览: {e}", "error")
            QMessageBox.warning(self, "路线预览失败", str(e))

    def write_route_preview_html(self, html_content):
        temp_file = tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            suffix=".html",
            prefix="sjtu_route_preview_",
            delete=False,
        )
        with temp_file:
            temp_file.write(html_content)
        self._route_preview_temp_files.append(temp_file.name)
        return os.path.abspath(temp_file.name)

    def stop_upload(self):
        """请求工作线程停止。"""
        if self._thread and self._thread.isRunning():
            self._thread.requestInterruption()
            self.log_output_text("已发送停止请求，请等待任务清理并退出...", "warning")
            self.stop_button.setEnabled(False)
            self.status_label.setText("状态: 正在停止...")
        else:
            self.log_output_text("没有运行中的任务可以停止。", "info")


    def update_progress(self, current, total, message):
        """更新进度条和状态信息"""
        self.progress_bar.setMaximum(total)
        self.progress_bar.setValue(current)
        self.status_label.setText(f"状态: {message}")

    def log_output_text(self, message, level="info"):
        """将日志信息添加到文本区域并按级别着色；条目同时留存，切主题后可重绘。"""
        is_progress = bool(re.match(r"^已完成\d+/\d+", message))
        if is_progress and self._log_entries and re.match(r"^已完成\d+/\d+", self._log_entries[-1][0]):
            # 进度类短消息（例如: 已完成1/25）替换最后一条，避免刷屏
            self._log_entries[-1] = (message, level)
            self._replace_last_log_line(message, level)
            return

        self._log_entries.append((message, level))
        if len(self._log_entries) > 500:
            del self._log_entries[:-500]
        self._insert_log_line(message, level)

    def _log_format(self, level):
        format = QTextCharFormat()
        format.setForeground(theme.log_color(self._theme, level))
        return format

    def _insert_log_line(self, message, level):
        cursor = self.log_output_area.textCursor()
        cursor.movePosition(QTextCursor.End)
        cursor.insertText(f"[{level.upper()}] {message}\n", self._log_format(level))
        self.log_output_area.ensureCursorVisible()

    def _replace_last_log_line(self, message, level):
        """替换最后一条日志（文档末尾恒有一个空块，要先退到真正有内容的块）。"""
        try:
            cursor = self.log_output_area.textCursor()
            cursor.movePosition(QTextCursor.End)
            block = cursor.block()
            if not block.text():
                cursor.movePosition(QTextCursor.PreviousBlock)
                block = cursor.block()
            cursor.setPosition(block.position())
            cursor.movePosition(QTextCursor.NextBlock, QTextCursor.KeepAnchor)
            cursor.removeSelectedText()
            cursor.insertText(f"[{level.upper()}] {message}\n", self._log_format(level))
            self.log_output_area.ensureCursorVisible()
        except Exception:
            self._insert_log_line(message, level)

    def clear_log_output(self):
        self._log_entries = []
        self.log_output_area.clear()

    def rebuild_log_output(self):
        """主题切换后按新配色重绘已有日志。"""
        if not hasattr(self, "log_output_area"):
            return
        entries = list(self._log_entries)
        self.log_output_area.clear()
        for message, level in entries:
            self._insert_log_line(message, level)

    def upload_finished(self, success, message):
        """上传任务完成后的处理"""
        self.start_button.setEnabled(True)
        self.stop_button.setEnabled(False)
        self.info_button.setEnabled(True)
        self.username_input.setEnabled(True)
        self.password_input.setEnabled(True)

        self.progress_bar.setValue(100)

        if success:
            self.status_label.setText("状态: 上传成功！")
            self.log_output_text(f"操作完成: {message}", "success")
            QMessageBox.information(self, "上传结果", message)
        else:
            self.status_label.setText("状态: 上传失败！")
            self.log_output_text(f"操作失败: {message}", "error")

        self._thread = None


    def show_info_dialog(self):
        """显示关于对话框（非模态）。

        使用 HelpWidget，作为非模态窗口显示，并保留对实例的引用以防止被垃圾回收。
        当窗口关闭时清理引用。
        """
        try:
            # 如果已有关于窗口实例：
            # - 若窗口仍可见，则激活并返回；
            # - 若已被隐藏/关闭但引用未清理，则清理引用并继续创建新的实例
            existing = getattr(self, "_help_window", None)
            if existing is not None:
                try:
                    if existing.isVisible():
                        try:
                            existing.activateWindow()
                            existing.raise_()
                        except Exception:
                            pass
                        return
                    else:
                        # 已存在但不可见，尝试移除事件过滤并清理引用以便重新创建
                        try:
                            existing.removeEventFilter(self)
                        except Exception:
                            pass
                        self._help_window = None
                except Exception:
                    self._help_window = None

            # 创建 HelpWidget 实例并以非模态方式显示
            self._help_window = HelpWidget(theme=self._theme)
            self._help_window.setWindowModality(Qt.WindowModality.NonModal)
            try:
                self._help_window.installEventFilter(self)
            except Exception:
                pass

            def _on_help_destroyed():
                try:
                    if getattr(self, "_help_window", None) is not None:
                        self._help_window = None
                except Exception:
                    self._help_window = None

            try:
                self._help_window.destroyed.connect(_on_help_destroyed)
            except Exception:
                pass

            # 显示窗口（非模态）
            self._help_window.show()

        except Exception as e:
            # 记录异常并弹出对话框，不影响后台线程
            self.log_output_text(f"无法显示关于窗口: {e}", "error")
            QMessageBox.warning(self, "显示失败", f"无法显示关于窗口: {e}")

    def open_route_generator(self):
        """打开路线规划器"""
        try:
            # 将导入移到方法开头，避免作用域问题
            from src.data_generator import generate_route_planner_html
            import os
            import webbrowser

            provider = self.map_provider_combo.currentData() if hasattr(self, "map_provider_combo") else "baidu"
            provider_label = "百度地图" if provider == "baidu" else "OpenStreetMap"

            # Inform user about the route planning process
            reply = QMessageBox.question(self, "路线规划",
                                    "此功能将启动路线规划器，您可以：\n\n"
                                    f"1. 在浏览器中打开在线地图（{provider_label}）\n"
                                    "2. 点击地图采集坐标点形成路线\n"
                                    "3. 点击\"下载路线 txt\"保存路线文件\n"
                                    "4. 回到软件，在\"预设路线\"中选择\"自定义...\"导入该 txt\n\n"
                                    "导入后路线会复制到软件旁的 Routes 文件夹，并在重启后继续保留。\n"
                                    "是否现在开始？",
                                    QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                                    QMessageBox.StandardButton.Yes)

            if reply == QMessageBox.StandardButton.Yes:
                try:
                    map_path = generate_route_planner_html(provider=provider)
                    webbrowser.open(f'file://{os.path.abspath(map_path)}')
                    
                    QMessageBox.information(self, "路线规划器", 
                                        "路线规划器已在浏览器中打开！\n\n"
                                        "请在地图上点击选择路径坐标点，\n"
                                        "点击\"下载路线 txt\"保存路线文件。\n\n"
                                        "下载完成后回到本软件，在\"预设路线\"下拉菜单中选择\"自定义...\"，\n"
                                        "然后导入刚刚下载的 txt 文件。")
                except Exception as e:
                    QMessageBox.critical(self, "错误", f"生成路线规划器失败：\n{str(e)}")
            else:
                selected_route = "未选择"
                if hasattr(self, "route_combo") and self.route_combo.currentData() != CUSTOM_ROUTE_ACTION:
                    selected_route = self.route_combo.currentText().strip() or selected_route

                QMessageBox.information(self, "当前路线",
                                    f"当前选择路线：{selected_route}\n\n"
                                    "如已有 txt 路线文件，可直接在\"预设路线\"中选择\"自定义...\"导入。\n"
                                    "如需重新设计路线，再点击\"设计/更新路线\"打开规划器。")

        except Exception as e:
            QMessageBox.critical(self, "错误", f"打开路线规划器时出错：\n{str(e)}")

    def eventFilter(self, watched, event):
        """拦截 HelpWidget 的 Close/Hide 事件，清理保存的引用以允许再次打开。"""
        try:
            if watched is getattr(self, "_help_window", None):
                # 使用数值来避免某些静态类型检查器对 QEvent 枚举成员的误报
                ev_type = event.type()
                if ev_type in (19, 5):  # 19 = Close, 5 = Hide
                    # 严禁在事件派发过程中移除过滤器或释放窗口：
                    # 那会在 Qt 还在遍历该窗口的过滤器链表/投递鼠标事件时改动它，
                    # 导致 macOS 上关闭关于窗口后崩溃。延后到本轮事件处理结束再做。
                    QTimer.singleShot(0, lambda w=watched: self.release_help_window(w))
        except Exception:
            pass

        return super().eventFilter(watched, event)

    def release_help_window(self, watched):
        """事件派发结束后再清理关于窗口的引用（由 eventFilter 延后调用）。"""
        try:
            if watched is not getattr(self, "_help_window", None):
                return
            try:
                watched.removeEventFilter(self)
            except Exception:
                pass
            self._help_window = None
        except Exception:
            pass

if __name__ == "__main__":
    set_windows_app_id()
    app = QApplication(sys.argv)
    app.setWindowIcon(QIcon(APP_ICON_PATH))
    ui = SportsUploaderUI()
    if not ui.show_commitment_dialog():
        sys.exit(0)
    ui.show()
    sys.exit(app.exec())

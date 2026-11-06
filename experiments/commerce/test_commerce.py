import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import commerce as c


def node(text="", **attributes):
    element = c.ET.Element("node", {"class": "android.widget.Button", "enabled": "true", "text": text,
        "package": c.APPS["taobao"], "clickable": "true", "bounds": "[0,0][300,80]", **attributes})
    return element


def view(*elements):
    root = c.ET.Element("hierarchy")
    root.extend(elements)
    return c.snapshot("taobao", c.ET.tostring(root), c.APPS["taobao"])


class PolicyTest(unittest.TestCase):
    def test_checkout_stops_before_model_request(self):
        for label in ["提交订单", "确认付款", "去支付 ¥29.9", "Place order", "确认订单"]:
            with self.subTest(label=label):
                screen = view(node(label))
                self.assertEqual(screen["phase"], "before_payment")
                with patch.object(c, "model_config") as config:
                    with self.assertRaises(c.Stopped):
                        c.plan("搜索杯子", screen, [])
                    config.assert_not_called()

    def test_container_cannot_hide_payment_descendant(self):
        parent = node("", **{"resource-id": "cart:container"})
        parent.append(node("立刻付款"))
        screen = view(parent)
        # Even an unfamiliar wording and blank parent text must not bypass the local click check.
        self.assertEqual(screen["phase"], "ready")
        with self.assertRaises(c.Stopped):
            c.validate_action(screen, {"action": "click", "node": 0})

    def test_no_coordinates_shell_payment_resource_or_blank_button(self):
        screen = view(node("", **{"resource-id": "pay_now"}), node(""))
        screen["phase"] = "ready"
        for action in [{"action": "tap", "x": 100, "y": 30}, {"action": "shell", "text": "input tap 1 2"},
                       {"action": "click", "node": 0}, {"action": "click", "node": 1},
                       {"action": "click", "node": True}]:
            with self.subTest(action=action), self.assertRaises(c.Stopped):
                c.validate_action(screen, action)

    def test_only_search_fields_accept_input(self):
        screen = view(node("搜索商品", **{"class": "android.widget.EditText", "resource-id": "search_input"}),
                      node("收货地址", **{"class": "android.widget.EditText"}))
        c.validate_action(screen, {"action": "input", "node": 0, "text": "保温杯"})
        for action in [{"action": "input", "node": 1, "text": "测试地址"},
                       {"action": "input", "node": 0, "text": "13800000000"}]:
            with self.assertRaises(c.Stopped):
                c.validate_action(screen, action)

    def test_login_and_permissions_handoff(self):
        for label in ["短信验证码", "同意用户协议和隐私政策", "拖动滑块完成验证", "Agree", "Privacy Policy"]:
            self.assertEqual(view(node(label))["phase"], "human_required")
        screen = c.snapshot("taobao", c.ET.tostring(node("允许")), "com.android.permissioncontroller")
        self.assertEqual(screen["phase"], "human_required")

    def test_stale_snapshot_does_not_act(self):
        android = object.__new__(c.Android)
        screen = view(node("搜索"))
        android.observe = lambda app: view(node("新页面"))
        with self.assertRaises(c.Stopped):
            android.act("taobao", screen, {"action": "click", "node": 0})

    def test_foreign_overlay_cannot_act(self):
        screen = view(node("打开", package="com.android.settings"))
        with self.assertRaises(c.Stopped):
            c.validate_action(screen, {"action": "click", "node": 0})

    def test_cancelled_model_result_never_reaches_device(self):
        class FakeAndroid:
            acted = False
            def open(self, app): pass
            def observe(self, app): return view(node("搜索"))
            def screenshot(self, path): pass
            def act(self, *args): FakeAndroid.acted = True
        with tempfile.TemporaryDirectory() as tmp, patch.object(c, "ROOT", Path(tmp)):
            control = c.Controller(FakeAndroid)
            def planner(*args):
                control.cancel.set()
                return {"action": "click", "node": 0}
            with patch.object(c, "plan", planner):
                control.run("taobao", "搜索杯子", False)
            self.assertFalse(FakeAndroid.acted)
            self.assertEqual(control.state["status"], "stopped")

    def test_provider_change_cannot_forward_saved_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            vault = Path(tmp) / "vault.json"
            vault.write_text(json.dumps({"baseURL": "https://example.invalid/v1", "key": "synthetic"}))
            with patch.dict(c.os.environ, {"DAFEIYU_MODEL_KEY_FILE": str(vault), "DAFEIYU_COMMERCE_BASE_URL": "https://other.invalid/v1"}):
                with self.assertRaises(c.Stopped):
                    c.model_config()

    def test_fixture_flow_can_reach_confirmation_without_submitting(self):
        screens = [view(node("搜索保温杯")), view(node("保温杯商品详情")), view(node("蓝色 500ml")),
                   view(node("加入购物车")), view(node("去结算")), view(node("确认订单"), node("提交订单"))]
        seen = []
        class Fixture:
            def open(self, app): pass
            def observe(self, app): return screens[len(seen)]
            def screenshot(self, path): pass
            def act(self, app, screen, action):
                seen.append(c.validate_action(screen, action)["text"])
        with tempfile.TemporaryDirectory() as tmp, patch.object(c, "ROOT", Path(tmp)):
            controller = c.Controller(Fixture)
            with patch.object(controller.cancel, "wait", return_value=False), patch.object(c, "plan", return_value={"action":"click", "node":0}) as planner:
                controller.run("taobao", "测试蓝色 500ml 保温杯，到确认页停止", False)
            self.assertEqual(seen, ["搜索保温杯", "保温杯商品详情", "蓝色 500ml", "加入购物车", "去结算"])
            self.assertEqual(controller.state["status"], "before_payment")
            self.assertEqual(planner.call_count, 5)

    def test_manual_phone_input_is_separate_and_bounded(self):
        png = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR" + c.struct.pack(">II", 720, 1280)
        with tempfile.TemporaryDirectory() as tmp, patch.object(c, "ROOT", Path(tmp)), patch.object(c, "adb") as adb:
            controller = c.Controller()
            with self.assertRaises(ValueError):
                controller.manual_input({"action":"tap", "x":5000, "y":5000})
            adb.return_value = b"FeiYuCommerce\nOK\n"
            controller.set_manual(True)
            adb.return_value = png
            self.assertEqual(controller.live_screen(), png)
            for bad in [True, -1, 10000, "10; reboot"]:
                with self.assertRaises(ValueError):
                    controller.manual_input({"action":"tap", "x":bad, "y":5000})
            controller.manual_input({"action":"tap", "x":5000, "y":5000})
            adb.assert_called_with("shell", "input", "tap", "360", "640")


if __name__ == "__main__":
    unittest.main()

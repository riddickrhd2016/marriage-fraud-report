import sys
import types
import contextlib
import importlib.util
from pathlib import Path


def load_module():
    module_path = Path(__file__).resolve().parents[1] / "scripts" / "vision-categorize.py"
    spec = importlib.util.spec_from_file_location("vision_categorize", module_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_missing_images_root(monkeypatch, capsys, tmp_path):
    vision_categorize = load_module()

    class DummyTensor:
        def to(self, device):
            return self

        def norm(self, dim=-1, keepdim=True):
            return self

        def __itruediv__(self, other):
            return self

    dummy_tensor = DummyTensor()

    class DummyModel:
        def encode_text(self, texts):
            return dummy_tensor

        def encode_image(self, image):
            return dummy_tensor

    dummy_open_clip = types.SimpleNamespace(
        create_model_and_transforms=lambda model, pretrained, device: (DummyModel(), None, lambda x: x),
        get_tokenizer=lambda model: (lambda texts: dummy_tensor),
    )

    @contextlib.contextmanager
    def no_grad():
        yield

    dummy_torch = types.SimpleNamespace(no_grad=no_grad)

    monkeypatch.setitem(sys.modules, "open_clip", dummy_open_clip)
    monkeypatch.setitem(sys.modules, "torch", dummy_torch)

    monkeypatch.setattr(
        sys,
        "argv",
        [
            "vision-categorize.py",
            "--images_root",
            str(tmp_path / "missing"),
            "--out_csv",
            str(tmp_path / "out.csv"),
        ],
    )

    vision_categorize.main()

    captured = capsys.readouterr()
    assert "Images root not found" in captured.out

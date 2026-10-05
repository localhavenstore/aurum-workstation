"""Offline tests (no system changes): W7 RAM -> model table, damaged-manifest refusal, pinning, localhost unit, test hooks off in release."""
import importlib.machinery, importlib.util, json, os, sys, tempfile
from pathlib import Path
import shutil
T = Path(tempfile.mkdtemp())
SRC = Path(__file__).resolve().parent.parent / "src"                       # the tree under review, not a fixed path
CP = T / "src"; shutil.copytree(SRC, CP); (CP / ".aurum-test-build").write_text("test hooks on\n")
os.environ.update(AURUM_ROOT=str(T / "root"))
loader = importlib.machinery.SourceFileLoader("aurum", str(CP / "aurum-ws"))
spec = importlib.util.spec_from_loader("aurum", loader); A = importlib.util.module_from_spec(spec); loader.exec_module(A)
F = []
def check(name, fn):
    try: fn(); print("ok  ", name)
    except Exception as e: F.append(name); print("FAIL", name, repr(e))

def w7():
    want = {4: "qwen3:1.7b", 7: "qwen3:1.7b", 8: "qwen3:4b-instruct", 15: "qwen3:4b-instruct", 16: "qwen3:8b", 31: "qwen3:8b", 32: "qwen3:14b", 128: "qwen3:14b"}
    for ram, tag in want.items():
        assert A.pick_model(ram, None)["tag"] == tag, (ram, A.pick_model(ram, None)["tag"])
    assert A.pick_model(4, "qwen3:8b")["tag"] == "qwen3:8b"
    try: A.pick_model(8, "llama:evil"); raise AssertionError("accepted")
    except A.Stop: pass
check("W7 RAM table: <8 -> 1.7b, 8-15 -> 4b, 16-31 -> 8b, >=32 -> 14b; --model only from the pinned list", w7)

def manifest_damage():
    A.STATE.mkdir(parents=True, exist_ok=True)
    A.MANIFEST.write_text("{broken")
    try: A.load_manifest(); raise AssertionError("accepted")
    except A.Stop as e: assert "damaged" in str(e)
    A.MANIFEST.write_text(json.dumps({"state": "INSTALLED", "steps": [{"id": "x", "state": "WEIRD"}]}))
    try: A.load_manifest(); raise AssertionError("accepted")
    except A.Stop: pass
    A.MANIFEST.unlink()
check("damaged / unknown-state manifest -> undo refuses (no guessing)", manifest_damage)

def pinned():
    r = A.REL
    assert len(r["ollama"]["sha256"]) == 64 and r["ollama"]["url"].startswith("https://github.com/ollama/ollama/releases/download/v")
    assert all(len(m["digest"]) == 64 and ":" in m["tag"] for m in r["models"])
    assert "install.sh" not in r["ollama"]["url"]
check("release metadata: Ollama tarball pinned by sha256 (never the install script); every model digest pinned", pinned)

def unit_localhost():
    assert "OLLAMA_HOST=127.0.0.1:11434" in A.UNIT_TEXT and "0.0.0.0" not in A.UNIT_TEXT
check("ollama.service binds 127.0.0.1 only", unit_localhost)
def hooks_off():
    import subprocess
    out = subprocess.run([sys.executable, "-B", "-c", "import importlib.machinery as m,importlib.util as u;"
        f"l=m.SourceFileLoader('a','{SRC / 'aurum-ws'}');s=u.spec_from_loader('a',l);a=u.module_from_spec(s);l.exec_module(a);"
        "print(a.TEST_BUILD, a.API, a.ROOT)"], capture_output=True, text=True, env=dict(os.environ, AURUM_OLLAMA_API="http://evil:1", AURUM_ROOT="/tmp/x"))
    assert out.stdout.split() == ["False", "http://127.0.0.1:11434", "/"], out.stdout + out.stderr
check("release build ignores AURUM_ROOT / AURUM_OLLAMA_API (test hooks only with the test marker)", hooks_off)
print(f"\n{len(F)} failure(s)"); sys.exit(1 if F else 0)

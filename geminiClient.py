"""
geminiClient.py
---------------
Python bridge to Gemini Robotics ER, a vision-language reasoning model. Called
from MATLAB (GeminiClient class) via py.geminiClient.GeminiClient().

Pure transport layer: no prompt construction or parsing here. Each MATLAB
reasoner (TaskPlanner / TaskVerifier) builds its own user prompt and system
instructions and parses the answer; box rescaling (0-1000 -> pixels) is done on
the MATLAB side.

The backend is chosen by GeminiClient.m from environment variables and passed in
(backend "enterprise" = Gemini Enterprise Agent Platform with ADC, "developer" =
Gemini Developer API with an API key), together with the ADC credentials or the
API key. google-genai reads the project and location from os.environ, which
GeminiClient.m syncs from MATLAB first.
"""

import io
import re

import numpy as np
from PIL import Image
from google import genai
from google.genai import types


MODEL = "gemini-robotics-er-2-preview"

# Pinned Gemini Developer API endpoint. An explicit base_url takes precedence
# over GOOGLE_GEMINI_BASE_URL, which a proxy environment may point elsewhere.
DEVELOPER_BASE_URL = "https://generativelanguage.googleapis.com/"

_MARKDOWN_FENCE_RE = re.compile(r"^```[a-z]*\n?|\n?```$", flags=re.MULTILINE)


class GeminiClient:
    def __init__(
        self,
        *,
        backend: str = "developer",
        credentials=None,
        api_key: str | None = None,
        temperature: float | None = 0.0,
        thinking_budget: int = 0,
    ):
        self._backend = backend
        # GeminiClient.m resolves the enterprise credentials and the developer
        # API key; project/location (enterprise) come from environment variables.
        if backend == "enterprise":
            self._client = genai.Client(vertexai=True, credentials=credentials)
        else:
            self._client = genai.Client(
                api_key=api_key,
                http_options=types.HttpOptions(base_url=DEVELOPER_BASE_URL))
        self._temperature = None if temperature is None else float(temperature)
        self._thinking_budget = int(thinking_budget)

    def __call__(
        self,
        user_prompt: str,
        images: list | None = None,
        *,
        instructions: str | None = None,
    ) -> str:
        """Send a prompt (and optional images) to the model; return its answer.

        images : list of uint8 (H, W, 3) RGB arrays, or None for a text-only
            call. Multiple images are labeled "Image 1:", "Image 2:", ...
        instructions : system instructions (role + scene + output schema).
        thinking_budget (constructor) : 0 = no thinking (fastest); -1 = unlimited.

        Returns the answer string with markdown fences stripped.
        """
        # Image(s) first, then the text: the order Gemini's prompting guide
        # recommends for image understanding.
        contents = []
        multiple_images = images is not None and len(images) > 1
        if images:
            for i, image in enumerate(images):
                if multiple_images:
                    contents.append(f"Image {i + 1}:")
                contents.append(types.Part.from_bytes(
                    data=self._encode_image(image), mime_type="image/png"))
        if user_prompt:
            contents.append(str(user_prompt))

        config = types.GenerateContentConfig(
            temperature=self._temperature,
            thinking_config=types.ThinkingConfig(
                thinking_budget=self._thinking_budget),
            system_instruction=str(instructions) if instructions else None,
        )
        response = self._client.models.generate_content(
            model=MODEL,
            contents=contents,
            config=config,
        )
        return self._strip_markdown_fences((response.text or "").strip())

    @property
    def model(self) -> str:
        """The model id requests are sent to (read-only)."""
        return MODEL

    @property
    def backend(self) -> str:
        """'enterprise' (Agent Platform, ADC) or 'developer' (API key)."""
        return self._backend

    @staticmethod
    def _encode_image(img_numpy: np.ndarray) -> bytes:
        """Compress a uint8 (H, W, 3) RGB array to PNG bytes."""
        if not isinstance(img_numpy, np.ndarray):
            raise TypeError("img_numpy must be a numpy array")
        if img_numpy.dtype != np.uint8:
            raise ValueError(f"image must be uint8, got {img_numpy.dtype}")
        if img_numpy.ndim != 3 or img_numpy.shape[2] != 3:
            raise ValueError(f"image must be (H, W, 3), got {img_numpy.shape}")

        buffer = io.BytesIO()
        Image.fromarray(img_numpy).save(buffer, format="PNG")
        return buffer.getvalue()

    @staticmethod
    def _strip_markdown_fences(text: str) -> str:
        """Remove surrounding ```lang ... ``` markdown fences, if present.
        The model often wraps JSON in a code fence even when asked for a raw
        string, which would break the caller's jsondecode."""
        return _MARKDOWN_FENCE_RE.sub("", text).strip()

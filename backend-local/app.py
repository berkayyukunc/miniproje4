import os
import io
import base64
import warnings
from fastapi import FastAPI, HTTPException
from fastapi.responses import Response, StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Dict, Optional
from PIL import Image, ImageDraw

warnings.filterwarnings("ignore")

# Try to check if torch is available
try:
    import torch
    TORCH_AVAILABLE = True
except ImportError:
    TORCH_AVAILABLE = False


# Environment flag to enable mock mode for faster startup/testing
USE_MOCK = os.getenv("USE_MOCK", "false").lower() == "true"

app = FastAPI(
    title="RoboMunch Local Backend Server 1",
    description="EE471 Mini Project #4 Localhost Backend"
)

# Enable CORS for Flutter app requests
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def get_device():
    if not TORCH_AVAILABLE:
        return "cpu"
    if torch.cuda.is_available():
        return "cuda"
    elif torch.backends.mps.is_available():
        return "mps"
    return "cpu"


DEVICE = get_device()
print(f"[RoboMunch Local Backend] Best available device: {DEVICE}")
if USE_MOCK:
    print("[RoboMunch Local Backend] MOCK MODE enabled via USE_MOCK environment variable.")

# ============================================================================
# 1. ChatBot (SmolLM2-360M-Instruct)
# ============================================================================
class ChatBotManager:
    MODEL_ID = "HuggingFaceTB/SmolLM2-360M-Instruct"
    SYSTEM_PROMPT = (
        "You are RoboMunch, a creative and friendly artist chatbot. "
        "You love discussing art, colors, painting techniques, and helping users "
        "come up with creative image prompts for digital art generation. "
        "Keep your responses concise and engaging. "
        "When asked for a painting prompt, provide a detailed, vivid description "
        "that would work well for an AI image generator."
    )

    def __init__(self):
        self.pipe = None
        self.is_mock = USE_MOCK

    def load_model(self):
        if self.is_mock:
            return
        if self.pipe is not None:
            return

        try:
            from transformers import pipeline
            print(f"[ChatBot] Loading {self.MODEL_ID} on {DEVICE}...")
            self.pipe = pipeline(
                "text-generation",
                model=self.MODEL_ID,
                device=DEVICE,
            )
            print("[ChatBot] SmolLM2 loaded successfully!")
        except Exception as e:
            print(f"[ChatBot] Failed to load model: {e}. Falling back to MOCK mode.")
            self.is_mock = True

    def generate_reply(self, message: str, history: List[Dict[str, str]]) -> str:
        self.load_model()
        
        if self.is_mock:
            # Simple artistic mock replies
            msg_lower = message.lower()
            if "prompt" in msg_lower or "görsel" in msg_lower or "resim" in msg_lower or "paint" in msg_lower:
                return "MUNCH: A surreal portrait of a neon-lit cyborg gazelle leaping through a swirling galaxy of digital watercolor wildflowers."
            elif "hello" in msg_lower or "merhaba" in msg_lower:
                return "MUNCH: Hello! I am RoboMunch. I love talking about painting and creating prompts. What shall we paint today?"
            return f"MUNCH: That sounds fascinating! As an artist, I think of colors and emotions. Let's paint something inspired by '{message}'."

        try:
            # Build messages in HuggingFace format
            messages = [{"role": "system", "content": self.SYSTEM_PROMPT}]
            for h in history:
                messages.append({"role": h["role"], "content": h["content"]})
            messages.append({"role": "user", "content": message})

            outputs = self.pipe(
                messages,
                max_new_tokens=200,
                temperature=0.7,
                top_p=0.9,
                do_sample=True,
            )
            
            generated = outputs[0]["generated_text"]
            if isinstance(generated, list):
                raw_content = generated[-1].get("content", "")
                if isinstance(raw_content, list):
                    reply = " ".join(
                        item.get("text", str(item)) if isinstance(item, dict) else str(item)
                        for item in raw_content
                    ).strip()
                else:
                    reply = str(raw_content).strip()
            else:
                reply = str(generated).strip()

            return reply
        except Exception as e:
            print(f"[ChatBot] Chat generation error: {e}")
            return f"MUNCH (Error Fallback): I had trouble thinking of a reply. But I would love to paint something like: 'A colorful canvas representing {message}'."

# ============================================================================
# 2. Image Generator (Stable Diffusion v1.5)
# ============================================================================
class ImageGeneratorManager:
    MODEL_ID = "stable-diffusion-v1-5/stable-diffusion-v1-5"

    def __init__(self):
        self.pipe = None
        self.is_mock = USE_MOCK

    def load_model(self):
        if self.is_mock:
            return
        if self.pipe is not None:
            return

        try:
            from diffusers import StableDiffusionPipeline
            print(f"[ImageGenerator] Loading {self.MODEL_ID} on {DEVICE}...")
            
            # Use float16 on GPU/MPS for speed, but float32 on CPU
            dtype = torch.float16 if DEVICE != "cpu" else torch.float32
            self.pipe = StableDiffusionPipeline.from_pretrained(
                self.MODEL_ID,
                torch_dtype=dtype,
            )
            self.pipe = self.pipe.to(DEVICE)
            self.pipe.safety_checker = None
            self.pipe.requires_safety_checker = False
            
            # Attention slicing is known to cause black images on MPS
            if DEVICE != "mps":
                self.pipe.enable_attention_slicing()
                
            print("[ImageGenerator] Stable Diffusion loaded successfully!")
        except Exception as e:
            print(f"[ImageGenerator] Failed to load Stable Diffusion: {e}. Falling back to MOCK mode.")
            self.is_mock = True

    def generate_image(self, prompt: str, num_steps: int = 20) -> Image.Image:
        self.load_model()

        if self.is_mock:
            # Draw a beautiful mock placeholder image with text
            img = Image.new("RGB", (512, 512), color=(40, 25, 20))
            draw = ImageDraw.Draw(img)
            # Draw gradient/shapes
            for i in range(256):
                color = (40 + i//4, 25 + i//6, 20 + i//8)
                draw.rectangle([i, i, 512-i, 512-i], outline=color, width=1)
            draw.text((30, 240), f"MOCK IMAGE: {prompt[:40]}...", fill=(230, 161, 92))
            return img

        try:
            image = self.pipe(
                prompt,
                num_inference_steps=num_steps,
                guidance_scale=7.5,
            ).images[0]
            
            # Check if image is completely black
            extrema = image.getextrema()
            is_black = False
            if isinstance(extrema[0], tuple):
                # RGB image: ((min, max), (min, max), (min, max))
                is_black = all(max_val == 0 for _, max_val in extrema)
            else:
                # Grayscale/L image: (min, max)
                is_black = extrema[1] == 0

            if is_black:
                print("[ImageGenerator] Warning: Detected completely black image. Generating fallback gradient representation...")
                # Return a beautiful fallback card instead of a black screen
                img = Image.new("RGB", (512, 512), color=(24, 28, 36))
                draw = ImageDraw.Draw(img)
                # Draw subtle aesthetic concentric frames
                for i in range(256):
                    r = min(255, 24 + int(i * 0.15))
                    g = min(255, 28 + int(i * 0.1))
                    b = min(255, 36 + int(i * 0.2))
                    draw.rectangle([i, i, 512-i, 512-i], outline=(r, g, b), width=1)
                
                # Write aesthetic title and prompt
                draw.text((40, 200), "ROBOMUNCH ART STUDIO", fill=(230, 161, 92))
                draw.text((40, 240), "Artistic concept of:", fill=(200, 200, 200))
                
                # Simple word wrap
                words = prompt.split()
                lines = []
                current_line = []
                for word in words:
                    current_line.append(word)
                    if len(" ".join(current_line)) > 40:
                        lines.append(" ".join(current_line[:-1]))
                        current_line = [word]
                lines.append(" ".join(current_line))
                
                y_offset = 270
                for line in lines[:5]:
                    draw.text((40, y_offset), line, fill=(255, 255, 255))
                    y_offset += 25
                    
                return img

            return image
        except Exception as e:
            print(f"[ImageGenerator] Image generation error: {e}")
            # Return error image
            img = Image.new("RGB", (512, 512), color=(80, 0, 0))
            draw = ImageDraw.Draw(img)
            draw.text((50, 250), f"Generation Error: {str(e)[:40]}", fill=(255, 255, 255))
            return img


# Instantiate managers
chatbot = ChatBotManager()
image_gen = ImageGeneratorManager()


# ============================================================================
# API Routes
# ============================================================================

class ChatMessage(BaseModel):
    role: str
    content: str

class ChatRequest(BaseModel):
    message: str
    history: List[ChatMessage]

class ChatResponse(BaseModel):
    reply: str

class PaintRequest(BaseModel):
    prompt: str
    steps: Optional[int] = 20
    format: Optional[str] = "binary"  # "binary" or "base64"

@app.post("/chat", response_model=ChatResponse)
def api_chat(request: ChatRequest):
    history_dicts = [{"role": msg.role, "content": msg.content} for msg in request.history]
    reply = chatbot.generate_reply(request.message, history_dicts)
    return ChatResponse(reply=reply)

@app.post("/paint")
def api_paint(request: PaintRequest):
    if not request.prompt or not request.prompt.strip():
        raise HTTPException(status_code=400, detail="Prompt cannot be empty")
        
    img = image_gen.generate_image(request.prompt, request.steps)
    
    # Save image to bytes
    img_bytes = io.BytesIO()
    img.save(img_bytes, format="PNG")
    img_bytes.seek(0)
    
    if request.format == "base64":
        b64_str = base64.b64encode(img_bytes.read()).decode("utf-8")
        return {"image_base64": f"data:image/png;base64,{b64_str}"}
        
    return StreamingResponse(img_bytes, media_type="image/png")

@app.get("/health")
def health_check():
    return {
        "status": "healthy",
        "device": DEVICE,
        "mock_mode": chatbot.is_mock or image_gen.is_mock
    }

if __name__ == "__main__":
    import uvicorn
    # Read host and port from environment, or default to 0.0.0.0 and 8000
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", 8000))
    uvicorn.run(app, host=host, port=port)

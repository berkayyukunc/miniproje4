import io
from django.http import JsonResponse, HttpResponse, HttpResponseBadRequest
from django.views.decorators.csrf import csrf_exempt
from PIL import Image

def get_image_from_request(request):
    """
    Helper to extract image from request.
    Handles multipart form-data ('image' or 'file' key) and raw request body.
    """
    if request.FILES:
        if 'image' in request.FILES:
            return request.FILES['image']
        elif 'file' in request.FILES:
            return request.FILES['file']
        # Fallback to the first file uploaded
        first_key = list(request.FILES.keys())[0]
        return request.FILES[first_key]
    
    # Fallback to raw binary body if no files uploaded via multipart
    if request.body:
        return io.BytesIO(request.body)
        
    return None

@csrf_exempt
def get_resolution(request):
    if request.method != 'POST':
        return HttpResponseBadRequest("Only POST method is allowed.")
        
    try:
        file_obj = get_image_from_request(request)
        if not file_obj:
            return JsonResponse({"error": "No image file provided in request."}, status=400)
            
        img = Image.open(file_obj)
        width, height = img.size
        return JsonResponse({
            "width": width,
            "height": height,
            "format": img.format
        })
    except Exception as e:
        return JsonResponse({"error": f"Failed to process image: {str(e)}"}, status=500)

@csrf_exempt
def convert_grayscale(request):
    if request.method != 'POST':
        return HttpResponseBadRequest("Only POST method is allowed.")
        
    try:
        file_obj = get_image_from_request(request)
        if not file_obj:
            return HttpResponse("No image file provided in request.", status=400, content_type="text/plain")
            
        img = Image.open(file_obj)
        # Convert to grayscale ("L" mode)
        gray_img = img.convert("L")
        
        # Save back to bytes
        img_bytes = io.BytesIO()
        gray_img.save(img_bytes, format="PNG")
        img_bytes.seek(0)
        
        return HttpResponse(img_bytes.read(), content_type="image/png")
    except Exception as e:
        return HttpResponse(f"Failed to process image: {str(e)}", status=500, content_type="text/plain")

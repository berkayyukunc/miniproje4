import io
from django.test import TestCase, Client
from django.urls import reverse
from PIL import Image

class ImageBackendTests(TestCase):
    def setUp(self):
        self.client = Client()
        
        # Create a simple test image in memory
        self.test_image_bytes = io.BytesIO()
        img = Image.new("RGB", (200, 100), color="blue")
        img.save(self.test_image_bytes, format="PNG")
        self.test_image_bytes.seek(0)
        
    def test_get_resolution(self):
        # Reset byte pointer
        self.test_image_bytes.seek(0)
        
        response = self.client.post(
            reverse('get_resolution'),
            {'image': self.test_image_bytes}
        )
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data['width'], 200)
        self.assertEqual(data['height'], 100)
        
    def test_convert_grayscale(self):
        # Reset byte pointer
        self.test_image_bytes.seek(0)
        
        response = self.client.post(
            reverse('convert_grayscale'),
            {'image': self.test_image_bytes}
        )
        
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response['content-type'], 'image/png')
        
        # Verify it's a valid grayscale image
        img_out = Image.open(io.BytesIO(response.content))
        self.assertEqual(img_out.mode, "L")
        self.assertEqual(img_out.size, (200, 100))

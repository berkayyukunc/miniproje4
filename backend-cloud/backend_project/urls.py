from django.urls import path
from backend_project import views

urlpatterns = [
    path('get/resolution', views.get_resolution, name='get_resolution'),
    path('convert/grayscale', views.convert_grayscale, name='convert_grayscale'),
]

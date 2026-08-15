/* Slim ftmodule.h for TinyOFD static FreeType build.
   Only drivers/renderers needed for OFD text (TrueType/CFF + SFNT + grayscale
   smooth renderer). Modeled on MuPDF's slimftmodules.h. */
FT_USE_MODULE( FT_Driver_ClassRec, tt_driver_class )
FT_USE_MODULE( FT_Driver_ClassRec, cff_driver_class )
FT_USE_MODULE( FT_Module_Class, psaux_module_class )
FT_USE_MODULE( FT_Module_Class, psnames_module_class )
FT_USE_MODULE( FT_Module_Class, pshinter_module_class )
FT_USE_MODULE( FT_Renderer_Class, ft_raster1_renderer_class )
FT_USE_MODULE( FT_Renderer_Class, ft_smooth_renderer_class )
FT_USE_MODULE( FT_Module_Class, sfnt_module_class )

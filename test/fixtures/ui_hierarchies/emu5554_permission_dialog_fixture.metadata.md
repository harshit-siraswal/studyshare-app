# emu5554_permission_dialog_fixture.xml Metadata

## Accessibility Note
- The node with resource-id `com.android.permissioncontroller:id/permission_icon` (class `android.widget.ImageView`) has an empty content-desc.
- This is a known accessibility issue in the emulator permission dialog.
- If the app cannot be changed to provide a meaningful content description, tests expecting accessibility compliance should skip or report this as known-broken.

## Drawing-order Note
- The node with resource-id `com.android.permissioncontroller:id/permission_message` has drawing-order="2".
- The next sibling container (button group) jumps to drawing-order="4"; drawing-order="3" is absent.
- This may be due to UIAutomator filtering or intentional omission. Tests should not rely on contiguous drawing-order values.
- All button nodes (allow_selected, allow_all, deny) remain correct.

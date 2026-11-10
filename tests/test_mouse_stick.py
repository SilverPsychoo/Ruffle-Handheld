"""Exercise the one-stick route with real SDL events on the host."""
import ctypes as C
import ctypes.util
import subprocess
import unittest

from tests.test_controller_routing import CORE, fields


def route(mode, database):
    return subprocess.run(
        ['bash', '-c', 'source "$1"; rh_route_mouse_stick "$2" "$3"',
         'stick-test', str(CORE / 'lib/control_profiles.sh'), mode, database],
        check=True, text=True, capture_output=True).stdout


class MouseStick(unittest.TestCase):
    def test_default_and_explicit_routes_preserve_each_pad(self):
        one = '11111111111111111111111111111111,One,leftx:a0,lefty:a1~,dpup:h0.1,a:b0,'
        two = '22222222222222222222222222222222,Two,leftx:a2,lefty:a3,rightx:a0,righty:a1,dpup:b4,'
        self.assertEqual(fields(route('', one)), fields(one))
        self.assertEqual(fields(route('auto', one)), fields(one))
        rows = route('left', one + '\n' + two).splitlines()
        self.assertEqual(fields(rows[0])['rightx'], 'a0')
        self.assertEqual(fields(rows[0])['righty'], 'a1~')
        self.assertNotIn('leftx', fields(rows[0]))
        self.assertEqual(fields(rows[0])['dpup'], 'h0.1')
        self.assertEqual(fields(rows[1])['rightx'], 'a2')
        self.assertEqual(fields(route('right', two)), fields(two))
        self.assertEqual(fields(route('right', one)), fields(one))
        swapped = fields(route('left', two))
        self.assertEqual(swapped['rightx'], 'a2')
        self.assertNotIn('leftx', swapped)
        self.assertEqual(swapped['dpup'], 'b4')

    def test_split_axes_comments_and_no_sticks(self):
        database = '# header\n33333333333333333333333333333333,Split,-leftx:-a0,+leftx:+a0,lefty:a1,\n44444444444444444444444444444444,No sticks,dpup:h0.1,'
        rows = route('left', database).splitlines()
        self.assertEqual(rows[0], '# header')
        self.assertEqual(fields(rows[1])['-rightx'], '-a0')
        self.assertEqual(fields(rows[1])['+rightx'], '+a0')
        self.assertEqual(fields(rows[2]), {'dpup': 'h0.1'})

    def test_left_stick_moves_sdl_cursor_axis_and_dpad_still_works(self):
        lib = ctypes.util.find_library('SDL2-2.0')
        if not lib:
            self.skipTest('host SDL2 unavailable')
        sdl = C.CDLL(lib)
        if not hasattr(sdl, 'SDL_JoystickAttachVirtual'):
            self.skipTest('host SDL2 predates virtual controllers')
        class Guid(C.Structure):
            _fields_ = [('data', C.c_uint8 * 16)]
        for name, args, result in [
            ('SDL_JoystickOpen', [C.c_int], C.c_void_p),
            ('SDL_JoystickGetGUID', [C.c_void_p], Guid),
            ('SDL_JoystickGetGUIDString', [Guid, C.c_char_p, C.c_int], None),
            ('SDL_GameControllerOpen', [C.c_int], C.c_void_p),
            ('SDL_GameControllerClose', [C.c_void_p], None),
            ('SDL_JoystickClose', [C.c_void_p], None),
            ('SDL_JoystickSetVirtualAxis', [C.c_void_p, C.c_int, C.c_int16], C.c_int),
            ('SDL_JoystickSetVirtualHat', [C.c_void_p, C.c_int, C.c_uint8], C.c_int),
            ('SDL_GameControllerGetAxis', [C.c_void_p, C.c_int], C.c_int16),
            ('SDL_GameControllerGetButton', [C.c_void_p, C.c_int], C.c_uint8),
        ]:
            fn = getattr(sdl, name); fn.argtypes = args; fn.restype = result
        self.assertEqual(sdl.SDL_Init(0x2200), 0)
        try:
            sdl.SDL_SetHint(b'SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS', b'1')
            index = sdl.SDL_JoystickAttachVirtual(1, 2, 12, 1)
            self.assertGreaterEqual(index, 0)
            joystick = sdl.SDL_JoystickOpen(index)
            guid = C.create_string_buffer(33)
            sdl.SDL_JoystickGetGUIDString(sdl.SDL_JoystickGetGUID(joystick), guid, 33)
            db = guid.value.decode() + ',One stick,a:b0,leftx:a0,lefty:a1,dpup:h0.1,platform:Linux,'
            self.assertGreaterEqual(sdl.SDL_GameControllerAddMapping(route('left', db).strip().encode()), 0)
            controller = sdl.SDL_GameControllerOpen(index)
            self.assertTrue(controller)
            for value in (-20000, 20000, 0):
                self.assertEqual(sdl.SDL_JoystickSetVirtualAxis(joystick, 0, value), 0)
                sdl.SDL_JoystickSetVirtualHat(joystick, 0, 1 if value else 0)
                sdl.SDL_PumpEvents(); sdl.SDL_JoystickUpdate()
                self.assertEqual(sdl.SDL_GameControllerGetAxis(controller, 2), value)
                self.assertEqual(sdl.SDL_GameControllerGetAxis(controller, 0), 0)
                self.assertEqual(sdl.SDL_GameControllerGetButton(controller, 11), 1 if value else 0)
            sdl.SDL_GameControllerClose(controller)
            sdl.SDL_JoystickClose(joystick)
        finally:
            sdl.SDL_Quit()

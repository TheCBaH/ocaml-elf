/* Dynamic executable fixture: calls into lib.so through the PLT and reads one of its objects. */
extern int libfn(int);
extern int lib_counter;

void _start(void) {
  volatile int r = libfn(lib_counter);
  (void)r;
  for (;;)
    ;
}

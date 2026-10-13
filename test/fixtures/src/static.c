/* Static executable fixture: no libc, no dynamic section. */
int data_word = 7;
int bss_word;
const char banner[] = "static fixture";

int compute(int x) { return x * 2 + data_word + bss_word; }

void _start(void) {
  bss_word = compute(banner[0]);
  for (;;)
    ;
}

{
/*
 Julia Set Fractal Generator
 -b version: Uses break to exit iteration early
 The Julia set is closely related to the Mandelbrot set but creates different patterns.
 Instead of varying c, we fix c and vary the starting point.
 This example uses a random c value to generate different fractal patterns each run.
 */

#pragma appname "Julia-Set-B"
#pragma decimals 3
#pragma console on
#pragma consolesize "680x740"
#pragma consoleposition "30,50"
#pragma ListASM on
#pragma FastPrint on
#pragma RunThreaded on
#pragma ftoi "truncate"
#pragma version on
#pragma modulename on
#pragma PasteToClipboard on
#pragma floattolerance 0.0001
#pragma GlobalStack 1024
#pragma FunctionStack 32
#pragma EvalStack 256
#pragma LocalStack 64
#pragma CreateLog off
#pragma DefaultFPS 32
#pragma ThreadKillWait 1800
#pragma asmdecimal on

    /* Julia set parameters - random c value for variety */
    c_real = random(400) - 200;   /* Random real part: -2.0 to 2.0 (scaled by 100) */
    c_imag = random(400) - 200;   /* Random imag part: -2.0 to 2.0 (scaled by 100) */

    left_edge   = -200;
    right_edge  =  200;
    top_edge    =  150;
    bottom_edge = -150;
    x_step      =    4;
    y_step      =    8;

    max_iter    =  100;

    y0 = top_edge;
    while y0 > bottom_edge {
        x0 = left_edge;
        while x0 < right_edge {
            /* Starting point for iteration */
            x = x0;
            y = y0;
            the_char = ' ';

            for (i = 0; i < max_iter; i++) {
                x_x = (x * x) / 100;
                y_y = (y * y) / 100;

                /* Check if point escapes to infinity */
                if (x_x + y_y > 400) {
                    /* Color based on iteration count */
                    the_char = '0' + i;
                    if i > 9 {
                        the_char = '@';
                    }
                    break;  // Exit iteration loop early
                }

                /* Julia set iteration: z = z^2 + c */
                temp_y = (x * y / 50) + c_imag;  /* 2*x*y + c_imag */
                x = x_x - y_y + c_real;
                y = temp_y;
            }
            putc(the_char);
            x0 = x0 + x_step;
        }
        putc('\n');
        y0 = y0 - y_step;
    }

    print("");
    print("Julia Set with c = ", c_real, " + ", c_imag, "i (scaled by 100)");
}

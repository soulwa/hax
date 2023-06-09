#![allow(dead_code)]
fn add3(x: usize, y: usize, z: usize) -> usize {
    x + y + z
}

fn local_mutation(mut x: usize) -> usize {
    let mut y = 0;
    if {
        x = x + 1;
        x > 3
    } {
        x = x - 3;
        let mut y = x / 2;
        for i in {
            y = y + 2;
            0
        }..10
        {
            y = x + i;
        }
        x + y
    } else {
        x = match x {
            12 => {
                y = x + y;
                3
            }
            13 => add3(
                x,
                {
                    x = x + 1;
                    123 + x
                },
                x,
            ),
            _ => 0,
        };
        x + y
    }
}

fn early_returns(mut x: usize) -> usize {
    return (123
        + if {
            if x > 3 {
                return 0;
            };
            x > 30
        } {
            match true {
                true => return 34,
                _ => 3,
            }
        } else {
            x = x + 9;
            x + 1
        })
        + x;
}

fn question_mark(mut x: usize) -> Result<usize, usize> {
    if x > 40usize {
        let mut y = 0;
        x = x + 3;
        y = x + y;
        if {
            x = x + y;
            x > 90usize
        } {
            Err(1u8)?
        }
    };
    match 3 {
        123 => 3,
        _ => 3,
    };
    Ok(3 + x)
}

struct Bar {
    a: bool,
    b: ([(bool, bool); 6], bool),
}
struct Foo {
    x: bool,
    y: (bool, Vec<Bar>),
    z: [Bar; 6],
    bar: Bar,
}
fn assign_non_trivial_lhs(mut foo: Foo) -> Foo {
    foo.x = true;
    foo.bar.a = true;
    foo.bar.b.0[3].1 = true;
    foo.z[3].a = true;
    foo.y.1[3].b.0[5].0 = true;
    foo
}

{application, blogerl,
 [{description, "A tiny blog engine that generates flat HTML and supports markdown"},
  {vsn, "0.9.0"},
  {modules, [blog]},
  {applications, [stdlib, kernel, erlydtl, markdown]}]}.

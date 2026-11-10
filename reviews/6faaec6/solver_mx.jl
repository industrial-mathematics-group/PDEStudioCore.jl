solvermx(p) = create_sim_data(collect(range(0.0, 1.0, length = 5)), [SVector(float(i) * get(p, :scale, 1.0)) for i in 1:5, j in 1:2], [0.0, 1.0], p)
markpost(d) = (d.metadata[:marked] = true; true)

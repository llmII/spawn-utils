# subprocess handling --------------------------------------------------------
# NOTE: The application using `pipe` or `process-spawn` becomes the buffer
# inbetween each process. While not ideal, if such were not done then pipe
# would have to attach the output of a process to the input of another without
# determining if a process ran successfully. The reason is that as a process
# produces output, it will fill the pipe, up to the operating system's buffer
# limit for pipes. At that point the process blocks until the pipe's buffer is
# emptied. A process's output, when redirected into a pipe simply bust have
# something that consumes it while it is being produced.
(defn- process-spawn [previous junction]
  (let [spawn-opts {:in (when previous :pipe) :out :pipe :err :pipe}
        ret @{}]
    #(printf "Junction: %q, Previous: %q" junction previous)
    (with [proc (os/spawn junction :px spawn-opts)]
      (try
        (do
          # Ensure you read and write pipe simutaneously, don't end up
          # hung because a pipe is stuck with a full buffer
          (ev/gather
            (when previous
              (:write (proc :in) previous)
              (:close (proc :in)))
            (put ret :out (:read (proc :out) :all))
            (put ret :err (:read (proc :err) :all)))
          (put ret :exit-code (:wait proc)))
        ([err]
          (errorf (string "Error <%V>: running `%s` with args [\"%s\"]\n\t"
                          "Spawned process stderr:\n\t\t%v")
                  err
                  (get junction 0)
                  (string/join (array/slice junction 1 -1) `" "`)
                  (ret :err)))))
    ret))

(defn- pump [data junction] # rename pump
  (if (function? junction)
    {:out (junction data)}
    (process-spawn data junction)))

(defn pipe [& plumbing]
  (let [plumbing    (if (array? plumbing) plumbing (array ;plumbing))
        return-type (when (keyword? (last plumbing)) (array/pop plumbing))
        tail        (when (bytes? (first plumbing))
                      (let [ret {:out (first plumbing)}]
                        (array/remove plumbing 0)
                        ret))
        state       @{:stack @[]
                      :tail (or tail {})}]
    (each junction plumbing
      (put state :tail (pump ((state :tail) :out) junction))
      (array/push (state :stack) (state :tail)))
    (match return-type
      :full state
      :last (state :tail)
      _ ((state :tail) :out))))

(comment

  (pp (pipe ["echo" "hello"] ["cat"])) # -> "hello\n"
  (pp (pipe "hello" ["cat"])) # -> "hello"
  (pp (pipe (pipe ["echo" "hello"]) ["cat"])) # -> "hello\n"
  (pp (pipe (fn [&] (pipe ["echo" "hello"])) ["cat"])) # -> "hello\n"

  )


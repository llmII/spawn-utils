# -------------------------------------------------------------------------- #
# Copyright (c) 2021 - llmII <dev@amlegion.org>D
# License: Open Works License v0.9.4 (LICENSE.md)
#
# spawn-utils
#
#   A library for dealing with subprocesses.

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
          (errorf (string "Error <%V>: running `%s` with args [\"%s\"]\n	"
                          "Spawned process stderr:\n	\t%v")
                  err
                  (get junction 0)
                  (string/join (array/slice junction 1 -1) `" "`)
                  (ret :err)))))
    ret))

(defn- pump [data junction] # rename pump
  (if (function? junction)
    {:out (junction data)}
    (process-spawn data junction)))

(defn pipe
  ```
  -> _:table|:buffer|throws error_

  	`plumbing` *:vararg*

  * Returns either a table `state`, table `tail`, or a `string|buffer`,
    determined by a keyword positioned as the last argument, or it's absence.

  * When returning a table `state` the structure of the table is like:

    `{:stack @[] :tail @{}}`

    The `stack` contains the output of every program in the pipe sequence that
    was ran, along with their exit codes, and their error output like:

    `{:out @"" :err @"" :exit-code 0}`

    The `tail` is the last element on the `stack`.

  * When returning a table `tail` its the same as the `state`'s `:tail`.

  * When returning a `string|buffer` it's the same as the `tail`'s `:out`.

  * The arguments to this function are variadic, the first argument should
    either be a `string` or a `tuple|array|function` and the last argument may
    be a `keyword`. All arguments inbetween must be of type
    `tuple|array|function`. The `tuple|array|function` arguments will be
    referred to as `normal arguments`.

  * If the first argument is a `string` it is used as input to the first
    `normal argument`. Otherwise the first `normal argument` will not have an
    input.

  * If the last argument is a `keyword` it effects the final output of the
    pipe. When the keyword is `:full` it returns a table with the full
    `state`. When the keyword is `:last`, it only returns the output of the
    processing of the last `normal argument`. When the last argument is
    omitted and is just a `normal argument`, `pipe` only returns the `:out`
    value from the `:tail`.

  * `normal argument`'s Are either a function of arity 1 that takes a
    string/buffer as an input, or a process specification, which is basically
    whatever `os/spawn` will accept as it's `args` parameter, which currently
    is an `array|tuple` with the first element being the name of the program
    and the rest of the elements being the value of arguments to be passed to
    the program.

  `pipe` calls each `normal argument` or runs a process with `os/spawn`
  otherwise, and pipes the input from each to the output of the next, in
  sequence, halting the pipeline if a function throws an error, or a process
  exits with a non-zero exit code, optionally allowing for the provision of
  input to the first `normal argument` processed by the pipeline. When an
  error is encountered, `pipe` throws to its caller. All processes within the
  pipeline, and their associated operating system pipes, are closed regardless
  of error. The application calling `pipe` operates as a buffer between each
  processed member of the pipeline.

  ```
  [& plumbing]
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

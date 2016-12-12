# frozen_string_literal: true
require 'lalka/version'
require 'dry-monads'

module Lalka
  # TODO: Invalidate resolve and reject at the same time

  class Task
    class << self
      def resolve(value)
        new do |t|
          t.resolve(value)
        end
      end

      def reject(error)
        new do |t|
          t.reject(error)
        end
      end
    end

    def initialize(&block)
      @computation = block
    end

    def fork_wait
      queue = Queue.new
      internal = Internal.new(queue)
      yield internal
      @computation.call(internal)
      queue.pop
    end

    def fork
      internal = InternalAsync.new
      yield internal
      @computation.call(internal)
      nil
    end

    def map
      Task.new do |t|
        fork do |this|
          this.on_sucess do |value|
            t.resolve(yield value)
          end

          this.on_error do |error|
            t.reject(error)
          end
        end
      end
    end

    def bind
      Task.new do |t|
        fork do |this|
          this.on_sucess do |first_value|
            other_task = yield first_value

            other_task.fork do |other|
              other.on_sucess do |second_value|
                t.resolve(second_value)
              end

              other.on_error do |error|
                t.reject(error)
              end
            end
          end

          this.on_error do |error|
            t.reject(error)
          end
        end
      end
    end

    def ap(other_task)
      Task.new do |t|
        q = Queue.new

        fork do |this|
          this.on_sucess do |fn|
            q.push [:fn, fn]
          end

          this.on_error do |error|
            q.push [:error, error]
          end
        end

        other_task.fork do |other|
          other.on_sucess do |value|
            q.push [:arg, value]
          end

          other.on_error do |error|
            q.push [:error, error]
          end
        end

        ap_aux(t, q, [false, nil], [false, nil])
      end
    end

    private

    def ap_aux(task, queue, fn, arg)
      if fn[0] && arg[0]
        result = fn[1].call(arg[1])
        task.resolve(result)
      else
        type, value = queue.pop

        case type
        when :error
          task.reject(value)
        when :fn
          ap_aux(task, queue, [true, value], arg)
        when :arg
          ap_aux(task, queue, fn, [true, value])
        else
          raise 'Unknown type'
        end
      end
    end
  end

  class InternalAsync
    def resolve(value)
      @on_sucess.call(value)
    end

    def reject(error)
      @on_error.call(error)
    end

    def on_sucess(&block)
      @on_sucess = block
      nil
    end

    def on_error(&block)
      @on_error = block
      nil
    end
  end

  class Internal
    def initialize(queue)
      @queue = queue
    end

    def resolve(value)
      result = @on_sucess.call(value)
      @queue.push Dry::Monads.Right(result)
    end

    def reject(error)
      result = @on_error.call(error)
      @queue.push Dry::Monads.Left(result)
    end

    def on_sucess(&block)
      @on_sucess = block
    end

    def on_error(&block)
      @on_error = block
    end
  end
end

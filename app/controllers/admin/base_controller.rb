module Admin
  class BaseController < ApplicationController
    tab :admin

    private

    # `route_ok` can be a proc, for routes that need the freshly created id.
    def save(record, route_ok, notice)
      if record.save
        redirect_to (route_ok.respond_to?(:call) ? route_ok.call : route_ok), notice: notice
      else
        flash.now[:alert] = record.errors.full_messages.join(", ")
        render(record.new_record? ? :new : :edit, status: :unprocessable_entity)
      end
    end
  end
end

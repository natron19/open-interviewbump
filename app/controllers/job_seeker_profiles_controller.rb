class JobSeekerProfilesController < ApplicationController
  def edit
    @profile = current_user.job_seeker_profile || current_user.build_job_seeker_profile
  end

  def update
    @profile = current_user.job_seeker_profile || current_user.build_job_seeker_profile
    @profile.assign_attributes(profile_params)

    if @profile.save
      redirect_to dashboard_path, notice: "Profile saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.require(:job_seeker_profile).permit(:background_summary)
  end
end
